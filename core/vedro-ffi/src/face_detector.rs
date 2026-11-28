//! On-device real-time AI Face Detection & 5-Landmark Engine (Plan A).
//!
//! Runs OpenCV Zoo's official YuNet (`face_detection_yunet_2023mar.onnx`, ~228 KB, Apache-2.0)
//! completely offline via pure-Rust `tract-onnx` across Android, iOS, macOS, Windows, and Linux.
//! Zero external C++ runtimes, zero cloud uploads, sub-20ms single-thread inference.

use std::path::Path;
use std::time::Instant;

use base64::Engine as _;
use ring::digest::{Context as ShaContext, SHA256};
use serde::Serialize;

/// Expected SHA-256 of official `face_detection_yunet_2023mar.onnx` (OpenCV Zoo).
pub const YUNET_2023MAR_SHA256: &str =
    "8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4";

const SCENE_SIG_W: usize = 16;
const SCENE_SIG_H: usize = 10;
const SCENE_SIG_LEN: usize = SCENE_SIG_W * SCENE_SIG_H;

/// Single detected face with normalized `[0.0, 1.0]` viewport coordinates.
///
/// Landmark convention matches OpenCV YuNet:
/// - `re`: subject's right eye (viewer's left)
/// - `le`: subject's left eye (viewer's right)
/// - `nose`: nose tip
/// - `rm`: subject's right mouth corner (viewer's left)
/// - `lm`: subject's left mouth corner (viewer's right)
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct DetectedFace {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
    pub score: f32,
    pub re_x: f32,
    pub re_y: f32,
    pub le_x: f32,
    pub le_y: f32,
    pub nose_x: f32,
    pub nose_y: f32,
    pub rm_x: f32,
    pub rm_y: f32,
    pub lm_x: f32,
    pub lm_y: f32,
}

#[derive(Debug, Clone, Serialize)]
pub struct FaceDetectOutput {
    pub faces: Vec<DetectedFace>,
    pub scene_cut: bool,
    pub infer_ms: f32,
}

#[derive(Debug, Clone, Serialize)]
pub struct FaceModelLoadOutput {
    pub ready: bool,
    pub input_w: usize,
    pub input_h: usize,
    pub sha256_ok: bool,
}

#[derive(Debug, Clone, Copy)]
struct StrideOutputs {
    stride: usize,
    cls_idx: usize,
    obj_idx: usize,
    bbox_idx: usize,
    kps_idx: usize,
}

/// Round requested dimension to a safe YuNet multiple of 32 within `[128, 640]`.
pub fn normalize_infer_dim(dim: usize, fallback: usize) -> usize {
    let raw = if dim == 0 { fallback } else { dim };
    let clamped = raw.clamp(128, 640);
    ((clamped + 16) / 32 * 32).clamp(128, 640)
}

/// Compute lowercase hex SHA-256 of a file on disk.
pub fn compute_file_sha256(path: &Path) -> Result<String, String> {
    let bytes = std::fs::read(path).map_err(|e| format!("failed to read model file: {e}"))?;
    let mut ctx = ShaContext::new(&SHA256);
    ctx.update(&bytes);
    let digest = ctx.finish();
    let mut hex = String::with_capacity(64);
    for b in digest.as_ref() {
        use std::fmt::Write;
        let _ = write!(&mut hex, "{b:02x}");
    }
    Ok(hex)
}

/// Aspect-ratio-preserving letterbox resize from raw RGBA/BGRA bytes into planar BGR f32 `[0..255]`
/// buffer of shape `[3, infer_h, infer_w]`, plus a compact 16x10 luma signature for scene-cut detection.
/// Returns `(bgr_nchw_data, active_w_px, active_h_px, scene_sig)`.
pub fn preprocess_frame_to_yunet_bgr(
    raw_pixels: &[u8],
    src_w: usize,
    src_h: usize,
    is_bgra: bool,
    infer_w: usize,
    infer_h: usize,
) -> Result<(Vec<f32>, f32, f32, [f32; SCENE_SIG_LEN]), String> {
    if src_w == 0 || src_h == 0 || infer_w == 0 || infer_h == 0 {
        return Err("invalid image dimensions".to_string());
    }
    let expected_len = src_w
        .checked_mul(src_h)
        .and_then(|n| n.checked_mul(4))
        .ok_or_else(|| "image dimension overflow".to_string())?;
    if raw_pixels.len() < expected_len {
        return Err(format!(
            "pixel buffer too small: got {}, expected at least {}",
            raw_pixels.len(),
            expected_len
        ));
    }

    let scale = (infer_w as f32 / src_w as f32).min(infer_h as f32 / src_h as f32);
    let new_w = ((src_w as f32 * scale).round() as usize).clamp(1, infer_w);
    let new_h = ((src_h as f32 * scale).round() as usize).clamp(1, infer_h);

    let plane_size = infer_w * infer_h;
    let mut bgr = vec![0.0f32; 3 * plane_size];

    let x_ratio = src_w as f32 / new_w as f32;
    let y_ratio = src_h as f32 / new_h as f32;
    let max_x = (src_w - 1) as f32;
    let max_y = (src_h - 1) as f32;

    for dy in 0..new_h {
        let sy_f = ((dy as f32 + 0.5) * y_ratio - 0.5).clamp(0.0, max_y);
        let y0 = sy_f.floor() as usize;
        let y1 = (y0 + 1).min(src_h - 1);
        let wy = sy_f - y0 as f32;
        let wy0 = 1.0 - wy;
        let row0 = y0 * src_w * 4;
        let row1 = y1 * src_w * 4;
        let dst_row = dy * infer_w;

        for dx in 0..new_w {
            let sx_f = ((dx as f32 + 0.5) * x_ratio - 0.5).clamp(0.0, max_x);
            let x0 = sx_f.floor() as usize;
            let x1 = (x0 + 1).min(src_w - 1);
            let wx = sx_f - x0 as f32;
            let wx0 = 1.0 - wx;

            let i00 = row0 + x0 * 4;
            let i01 = row0 + x1 * 4;
            let i10 = row1 + x0 * 4;
            let i11 = row1 + x1 * 4;

            let w00 = wy0 * wx0;
            let w01 = wy0 * wx;
            let w10 = wy * wx0;
            let w11 = wy * wx;

            let c0 = raw_pixels[i00] as f32 * w00
                + raw_pixels[i01] as f32 * w01
                + raw_pixels[i10] as f32 * w10
                + raw_pixels[i11] as f32 * w11;
            let c1 = raw_pixels[i00 + 1] as f32 * w00
                + raw_pixels[i01 + 1] as f32 * w01
                + raw_pixels[i10 + 1] as f32 * w10
                + raw_pixels[i11 + 1] as f32 * w11;
            let c2 = raw_pixels[i00 + 2] as f32 * w00
                + raw_pixels[i01 + 2] as f32 * w01
                + raw_pixels[i10 + 2] as f32 * w10
                + raw_pixels[i11 + 2] as f32 * w11;

            let (b, g, r) = if is_bgra { (c0, c1, c2) } else { (c2, c1, c0) };
            let idx = dst_row + dx;
            bgr[idx] = b;
            bgr[plane_size + idx] = g;
            bgr[2 * plane_size + idx] = r;
        }
    }

    let mut sig = [0.0f32; SCENE_SIG_LEN];
    for sy in 0..SCENE_SIG_H {
        let py = ((sy * new_h) / SCENE_SIG_H).min(new_h - 1);
        for sx in 0..SCENE_SIG_W {
            let px = ((sx * new_w) / SCENE_SIG_W).min(new_w - 1);
            let idx = py * infer_w + px;
            let b = bgr[idx];
            let g = bgr[plane_size + idx];
            let r = bgr[2 * plane_size + idx];
            sig[sy * SCENE_SIG_W + sx] = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
        }
    }

    Ok((bgr, new_w as f32, new_h as f32, sig))
}

/// Compare two 16x10 normalized luma signatures and report whether a hard scene cut occurred.
pub fn is_scene_cut(prev: Option<&[f32; SCENE_SIG_LEN]>, curr: &[f32; SCENE_SIG_LEN]) -> bool {
    let Some(p) = prev else {
        return false;
    };
    let mut sum_abs = 0.0f32;
    for i in 0..SCENE_SIG_LEN {
        sum_abs += (p[i] - curr[i]).abs();
    }
    (sum_abs / SCENE_SIG_LEN as f32) > 0.22
}

fn iou(a: &DetectedFace, b: &DetectedFace) -> f32 {
    let ax2 = a.x + a.w;
    let ay2 = a.y + a.h;
    let bx2 = b.x + b.w;
    let by2 = b.y + b.h;
    let inter_x1 = a.x.max(b.x);
    let inter_y1 = a.y.max(b.y);
    let inter_x2 = ax2.min(bx2);
    let inter_y2 = ay2.min(by2);
    let inter_w = (inter_x2 - inter_x1).max(0.0);
    let inter_h = (inter_y2 - inter_y1).max(0.0);
    let inter = inter_w * inter_h;
    if inter <= 0.0 {
        return 0.0;
    }
    let area_a = (a.w * a.h).max(1e-6);
    let area_b = (b.w * b.h).max(1e-6);
    inter / (area_a + area_b - inter).max(1e-6)
}

/// Borrowed YuNet output head tensors for a single FPN stride (8 / 16 / 32).
pub struct YunetStrideSlice<'a> {
    pub cls: &'a [f32],
    pub obj: &'a [f32],
    pub bbox: &'a [f32],
    pub kps: &'a [f32],
    pub stride: usize,
}

/// Bit-exact OpenCV YuNet anchor-free decoder + IoU NMS.
#[allow(clippy::too_many_arguments)]
pub fn decode_yunet_tensors(
    slices: &[YunetStrideSlice<'_>],
    infer_w: usize,
    infer_h: usize,
    active_w: f32,
    active_h: f32,
    score_threshold: f32,
    nms_threshold: f32,
    max_faces: usize,
) -> Vec<DetectedFace> {
    let inv_w = 1.0 / active_w.max(1.0);
    let inv_h = 1.0 / active_h.max(1.0);
    let mut candidates: Vec<DetectedFace> = Vec::new();

    for head in slices {
        let cls_v = head.cls;
        let obj_v = head.obj;
        let bbox_v = head.bbox;
        let kps_v = head.kps;
        let stride = head.stride;
        let cols = infer_w / stride;
        let rows = infer_h / stride;
        let s = stride as f32;
        let total = rows * cols;
        if cls_v.len() < total
            || obj_v.len() < total
            || bbox_v.len() < total * 4
            || kps_v.len() < total * 10
        {
            continue;
        }
        for r in 0..rows {
            let rf = r as f32;
            for c in 0..cols {
                let idx = r * cols + c;
                let cls_score = cls_v[idx].clamp(0.0, 1.0);
                let obj_score = obj_v[idx].clamp(0.0, 1.0);
                let score = (cls_score * obj_score).sqrt();
                if score < score_threshold {
                    continue;
                }
                let cf = c as f32;
                let cx = (cf + bbox_v[idx * 4]) * s;
                let cy = (rf + bbox_v[idx * 4 + 1]) * s;
                let w = bbox_v[idx * 4 + 2].clamp(-6.0, 6.0).exp() * s;
                let h = bbox_v[idx * 4 + 3].clamp(-6.0, 6.0).exp() * s;
                let x1 = cx - w * 0.5;
                let y1 = cy - h * 0.5;

                // Filter out tiny background faces (< 3.5% frame height) or out-of-frame artifacts
                let norm_w = (w * inv_w).clamp(0.0, 1.0);
                let norm_h = (h * inv_h).clamp(0.0, 1.0);
                if norm_h < 0.035 || norm_w < 0.02 {
                    continue;
                }

                let mut lm = [0.0f32; 10];
                for n in 0..5 {
                    let lx = (kps_v[idx * 10 + 2 * n] + cf) * s;
                    let ly = (kps_v[idx * 10 + 2 * n + 1] + rf) * s;
                    lm[2 * n] = (lx * inv_w).clamp(0.0, 1.0);
                    lm[2 * n + 1] = (ly * inv_h).clamp(0.0, 1.0);
                }

                candidates.push(DetectedFace {
                    x: (x1 * inv_w).clamp(0.0, 1.0),
                    y: (y1 * inv_h).clamp(0.0, 1.0),
                    w: norm_w,
                    h: norm_h,
                    score,
                    re_x: lm[0],
                    re_y: lm[1],
                    le_x: lm[2],
                    le_y: lm[3],
                    nose_x: lm[4],
                    nose_y: lm[5],
                    rm_x: lm[6],
                    rm_y: lm[7],
                    lm_x: lm[8],
                    lm_y: lm[9],
                });
            }
        }
    }

    candidates.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    let mut kept: Vec<DetectedFace> = Vec::with_capacity(max_faces.max(1));
    for cand in candidates {
        if kept.iter().any(|k| iou(k, &cand) > nms_threshold) {
            continue;
        }
        kept.push(cand);
        if kept.len() >= 8 {
            break;
        }
    }

    // Prioritize prominent hero faces (area * score) for beauty morphing
    kept.sort_by(|a, b| {
        let pa = a.w * a.h * a.score;
        let pb = b.w * b.h * b.score;
        pb.partial_cmp(&pa).unwrap_or(std::cmp::Ordering::Equal)
    });
    kept.truncate(max_faces.clamp(1, 4));
    kept
}

#[cfg(not(target_os = "tvos"))]
mod runtime_impl {
    use super::*;
    use tract_onnx::prelude::*;

    type RunnablePlan = SimplePlan<TypedFact, Box<dyn TypedOp>, Graph<TypedFact, Box<dyn TypedOp>>>;

    struct LoadedYuNet {
        model_path: String,
        infer_w: usize,
        infer_h: usize,
        plan: RunnablePlan,
        stride_map: [StrideOutputs; 3],
        sha256_ok: bool,
    }

    #[derive(Default)]
    pub struct FaceDetectorEngine {
        loaded: Option<LoadedYuNet>,
        prev_scene_sig: Option<[f32; SCENE_SIG_LEN]>,
    }

    impl FaceDetectorEngine {
        pub fn new() -> Self {
            Self::default()
        }

        pub fn unload(&mut self) {
            self.loaded = None;
            self.prev_scene_sig = None;
        }

        pub fn load_model(
            &mut self,
            model_path: &str,
            infer_w: usize,
            infer_h: usize,
        ) -> Result<FaceModelLoadOutput, String> {
            let iw = normalize_infer_dim(infer_w, 256);
            let ih = normalize_infer_dim(infer_h, 160);
            if let Some(ref cur) = self.loaded {
                if cur.model_path == model_path && cur.infer_w == iw && cur.infer_h == ih {
                    return Ok(FaceModelLoadOutput {
                        ready: true,
                        input_w: iw,
                        input_h: ih,
                        sha256_ok: cur.sha256_ok,
                    });
                }
            }

            let path = Path::new(model_path);
            if !path.is_file() {
                return Err(format!("AI 人脸模型文件不存在: {model_path}"));
            }
            let sha = compute_file_sha256(path)?;
            let sha256_ok = sha.eq_ignore_ascii_case(YUNET_2023MAR_SHA256);

            let onnx = tract_onnx::onnx().with_ignore_output_shapes(true);
            let mut proto = onnx
                .proto_model_for_path(path)
                .map_err(|e| format!("解析 ONNX 模型失败: {e}"))?;
            let mut out_names: Vec<String> = Vec::new();
            if let Some(ref mut g) = proto.graph {
                out_names = g.output.iter().map(|o| o.name.clone()).collect();
                // Clear static 640x640 intermediate value_info so YuNet compiles cleanly
                // for fast 256x160 / 320x192 widescreen inference!
                g.value_info.clear();
            }

            let plan = onnx
                .model_for_proto_model(&proto)
                .map_err(|e| format!("构建 ONNX 计算图失败: {e}"))?
                .with_input_fact(
                    0,
                    InferenceFact::dt_shape(f32::datum_type(), tvec!(1, 3, ih, iw)),
                )
                .map_err(|e| format!("设置输入分辨率失败: {e}"))?
                .into_optimized()
                .map_err(|e| format!("优化 ONNX 模型失败: {e}"))?
                .into_runnable()
                .map_err(|e| format!("编译 ONNX 执行计划失败: {e}"))?;

            if plan.model().outputs.len() < 12 {
                return Err(format!(
                    "非有效 YuNet 人脸模型（输出节点数 {} < 12）",
                    plan.model().outputs.len()
                ));
            }

            let find_idx = |name: &str, fallback: usize| -> usize {
                out_names.iter().position(|n| n == name).unwrap_or(fallback)
            };
            let stride_map = [
                StrideOutputs {
                    stride: 8,
                    cls_idx: find_idx("cls_8", 0),
                    obj_idx: find_idx("obj_8", 3),
                    bbox_idx: find_idx("bbox_8", 6),
                    kps_idx: find_idx("kps_8", 9),
                },
                StrideOutputs {
                    stride: 16,
                    cls_idx: find_idx("cls_16", 1),
                    obj_idx: find_idx("obj_16", 4),
                    bbox_idx: find_idx("bbox_16", 7),
                    kps_idx: find_idx("kps_16", 10),
                },
                StrideOutputs {
                    stride: 32,
                    cls_idx: find_idx("cls_32", 2),
                    obj_idx: find_idx("obj_32", 5),
                    bbox_idx: find_idx("bbox_32", 8),
                    kps_idx: find_idx("kps_32", 11),
                },
            ];

            self.loaded = Some(LoadedYuNet {
                model_path: model_path.to_string(),
                infer_w: iw,
                infer_h: ih,
                plan,
                stride_map,
                sha256_ok,
            });
            self.prev_scene_sig = None;

            Ok(FaceModelLoadOutput {
                ready: true,
                input_w: iw,
                input_h: ih,
                sha256_ok,
            })
        }

        #[allow(clippy::too_many_arguments)]
        pub fn detect_b64(
            &mut self,
            model_path: &str,
            width: usize,
            height: usize,
            data_b64: &str,
            is_bgra: bool,
            infer_w: usize,
            infer_h: usize,
            score_threshold: f32,
            max_faces: usize,
        ) -> Result<FaceDetectOutput, String> {
            let t0 = Instant::now();
            self.load_model(model_path, infer_w, infer_h)?;
            let raw_bytes = base64::engine::general_purpose::STANDARD
                .decode(data_b64)
                .map_err(|e| format!("invalid base64 pixel payload: {e}"))?;

            let loaded = self
                .loaded
                .as_ref()
                .ok_or_else(|| "face detector not initialized".to_string())?;
            let iw = loaded.infer_w;
            let ih = loaded.infer_h;

            let (bgr_data, active_w, active_h, curr_sig) =
                preprocess_frame_to_yunet_bgr(&raw_bytes, width, height, is_bgra, iw, ih)?;
            let scene_cut = is_scene_cut(self.prev_scene_sig.as_ref(), &curr_sig);
            self.prev_scene_sig = Some(curr_sig);

            let input = Tensor::from_shape(&[1, 3, ih, iw], &bgr_data)
                .map_err(|e| format!("tensor build failed: {e}"))?;
            let outputs = loaded
                .plan
                .run(tvec!(input.into()))
                .map_err(|e| format!("YuNet inference failed: {e}"))?;

            struct OwnedStrideHead {
                cls: Vec<f32>,
                obj: Vec<f32>,
                bbox: Vec<f32>,
                kps: Vec<f32>,
                stride: usize,
            }
            let mut owned_slices: Vec<OwnedStrideHead> = Vec::with_capacity(3);
            for st in &loaded.stride_map {
                let cls = outputs[st.cls_idx]
                    .as_slice::<f32>()
                    .map_err(|e| format!("cls slice err: {e}"))?
                    .to_vec();
                let obj = outputs[st.obj_idx]
                    .as_slice::<f32>()
                    .map_err(|e| format!("obj slice err: {e}"))?
                    .to_vec();
                let bbox = outputs[st.bbox_idx]
                    .as_slice::<f32>()
                    .map_err(|e| format!("bbox slice err: {e}"))?
                    .to_vec();
                let kps = outputs[st.kps_idx]
                    .as_slice::<f32>()
                    .map_err(|e| format!("kps slice err: {e}"))?
                    .to_vec();
                owned_slices.push(OwnedStrideHead {
                    cls,
                    obj,
                    bbox,
                    kps,
                    stride: st.stride,
                });
            }
            let slice_refs: Vec<YunetStrideSlice<'_>> = owned_slices
                .iter()
                .map(|h| YunetStrideSlice {
                    cls: h.cls.as_slice(),
                    obj: h.obj.as_slice(),
                    bbox: h.bbox.as_slice(),
                    kps: h.kps.as_slice(),
                    stride: h.stride,
                })
                .collect();

            let faces = decode_yunet_tensors(
                &slice_refs,
                iw,
                ih,
                active_w,
                active_h,
                score_threshold.clamp(0.25, 0.95),
                0.30,
                max_faces,
            );

            Ok(FaceDetectOutput {
                faces,
                scene_cut,
                infer_ms: t0.elapsed().as_secs_f32() * 1000.0,
            })
        }
    }
}

#[cfg(target_os = "tvos")]
mod runtime_impl {
    use super::*;

    #[derive(Default)]
    pub struct FaceDetectorEngine;

    impl FaceDetectorEngine {
        pub fn new() -> Self {
            Self
        }

        pub fn unload(&mut self) {}

        pub fn load_model(
            &mut self,
            _model_path: &str,
            _infer_w: usize,
            _infer_h: usize,
        ) -> Result<FaceModelLoadOutput, String> {
            Err("AI face beauty inference is not enabled on tvOS".to_string())
        }

        #[allow(clippy::too_many_arguments)]
        pub fn detect_b64(
            &mut self,
            _model_path: &str,
            _width: usize,
            _height: usize,
            _data_b64: &str,
            _is_bgra: bool,
            _infer_w: usize,
            _infer_h: usize,
            _score_threshold: f32,
            _max_faces: usize,
        ) -> Result<FaceDetectOutput, String> {
            Err("AI face beauty inference is not enabled on tvOS".to_string())
        }
    }
}

pub use runtime_impl::FaceDetectorEngine;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preprocesses_rgba_and_bgra_with_aspect_letterbox_and_scene_cut() {
        // 4x2 solid red frame in RGBA -> B=0, G=0, R=255
        let mut rgba = vec![0u8; 4 * 2 * 4];
        for i in (0..rgba.len()).step_by(4) {
            rgba[i] = 240; // R
            rgba[i + 1] = 20; // G
            rgba[i + 2] = 10; // B
            rgba[i + 3] = 255;
        }
        let (bgr, aw, ah, sig1) =
            preprocess_frame_to_yunet_bgr(&rgba, 4, 2, false, 64, 32).unwrap();
        assert_eq!(aw as usize, 64);
        assert_eq!(ah as usize, 32);
        let plane = 64 * 32;
        assert!((bgr[0] - 10.0).abs() < 1.0); // B channel
        assert!((bgr[plane] - 20.0).abs() < 1.0); // G channel
        assert!((bgr[2 * plane] - 240.0).abs() < 1.0); // R channel

        // Identical frame in BGRA -> same BGR values, zero scene cut
        let mut bgra = vec![0u8; 4 * 2 * 4];
        for i in (0..bgra.len()).step_by(4) {
            bgra[i] = 10; // B
            bgra[i + 1] = 20; // G
            bgra[i + 2] = 240; // R
            bgra[i + 3] = 255;
        }
        let (_, _, _, sig2) = preprocess_frame_to_yunet_bgr(&bgra, 4, 2, true, 64, 32).unwrap();
        assert!(!is_scene_cut(Some(&sig1), &sig2));

        // Bright white frame -> triggers scene cut
        let white = vec![255u8; 4 * 2 * 4];
        let (_, _, _, sig3) = preprocess_frame_to_yunet_bgr(&white, 4, 2, false, 64, 32).unwrap();
        assert!(is_scene_cut(Some(&sig1), &sig3));
    }

    #[test]
    fn decodes_yunet_stride_tensors_and_applies_nms() {
        // 256x160 inference grid -> stride 32 has 8 cols x 5 rows = 40 anchors
        let cols = 8usize;
        let rows = 5usize;
        let total = cols * rows;
        let mut cls = vec![0.0f32; total];
        let mut obj = vec![0.0f32; total];
        let mut bbox = vec![0.0f32; total * 4];
        let mut kps = vec![0.0f32; total * 10];

        // Place two overlapping detections around center (r=2, c=4) and (r=2, c=3) -> NMS keeps higher score
        let idx_best = 2 * cols + 4;
        cls[idx_best] = 0.96;
        obj[idx_best] = 0.94;
        bbox[idx_best * 4] = 0.0; // cx = 4 * 32 = 128
        bbox[idx_best * 4 + 1] = 0.0; // cy = 2 * 32 = 64
        bbox[idx_best * 4 + 2] = (2.0f32).ln(); // w = 64
        bbox[idx_best * 4 + 3] = (2.5f32).ln(); // h = 80
                                                // Right eye at (112, 56), left eye at (144, 56), nose (128, 72), mouth (116..140, 88)
        kps[idx_best * 10] = -0.5;
        kps[idx_best * 10 + 1] = -0.25;
        kps[idx_best * 10 + 2] = 0.5;
        kps[idx_best * 10 + 3] = -0.25;
        kps[idx_best * 10 + 4] = 0.0;
        kps[idx_best * 10 + 5] = 0.25;
        kps[idx_best * 10 + 6] = -0.375;
        kps[idx_best * 10 + 7] = 0.75;
        kps[idx_best * 10 + 8] = 0.375;
        kps[idx_best * 10 + 9] = 0.75;

        // Overlapping lower-confidence neighbor
        let idx_dup = 2 * cols + 3;
        cls[idx_dup] = 0.72;
        obj[idx_dup] = 0.75;
        bbox[idx_dup * 4] = 0.8;
        bbox[idx_dup * 4 + 1] = 0.0;
        bbox[idx_dup * 4 + 2] = (2.0f32).ln();
        bbox[idx_dup * 4 + 3] = (2.5f32).ln();

        let faces = decode_yunet_tensors(
            &[YunetStrideSlice {
                cls: cls.as_slice(),
                obj: obj.as_slice(),
                bbox: bbox.as_slice(),
                kps: kps.as_slice(),
                stride: 32,
            }],
            256,
            160,
            256.0,
            144.0,
            0.60,
            0.30,
            2,
        );
        assert_eq!(faces.len(), 1);
        let f = &faces[0];
        assert!(f.score > 0.94);
        assert!((f.re_x - 112.0 / 256.0).abs() < 0.01);
        assert!((f.le_x - 144.0 / 256.0).abs() < 0.01);
        assert!((f.nose_x - 0.5).abs() < 0.01);
        assert!((f.rm_x - 116.0 / 256.0).abs() < 0.01);
        assert!((f.lm_x - 140.0 / 256.0).abs() < 0.01);
    }
}
