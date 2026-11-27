#include "my_application.h"

#include <cstring>
#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* main_window;
  gboolean is_fullscreen;
  guint inhibit_cookie;
  FlMethodChannel* hw_channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static gboolean is_allowed_http_url(const gchar* url) {
  if (!url) return FALSE;
  g_autofree gchar* lower = g_ascii_strdown(url, 8);
  if (!g_str_has_prefix(lower, "http://") && !g_str_has_prefix(lower, "https://")) {
    return FALSE;
  }
  for (const gchar* p = url; *p; ++p) {
    if (static_cast<unsigned char>(*p) <= 0x20) return FALSE;
  }
  return TRUE;
}

static void on_main_window_destroy(GtkWidget* widget, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (GTK_WIDGET(self->main_window) == widget) {
    self->main_window = nullptr;
  }
}

static gboolean on_window_state_event(GtkWidget* widget,
                                      GdkEventWindowState* event,
                                      gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  gboolean now_fs = (event->new_window_state & GDK_WINDOW_STATE_FULLSCREEN) != 0;
  if (now_fs != self->is_fullscreen) {
    self->is_fullscreen = now_fs;
    if (self->hw_channel) {
      g_autoptr(FlValue) map = fl_value_new_map();
      fl_value_set_string_take(map, "fullscreen", fl_value_new_bool(now_fs));
      fl_method_channel_invoke_method(self->hw_channel, "fullscreenChanged", map,
                                      nullptr, nullptr, nullptr);
    }
  }
  return FALSE;
}

static void on_drag_data_received(GtkWidget* widget,
                                  GdkDragContext* context,
                                  gint x,
                                  gint y,
                                  GtkSelectionData* data,
                                  guint info,
                                  guint time,
                                  gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  gchar** uris = gtk_selection_data_get_uris(data);
  if (uris && self->hw_channel) {
    g_autoptr(FlValue) list = fl_value_new_list();
    for (gchar** p = uris; *p; ++p) {
      g_autofree gchar* path = g_filename_from_uri(*p, nullptr, nullptr);
      if (path && *path) {
        fl_value_append_take(list, fl_value_new_string(path));
      }
    }
    if (fl_value_get_length(list) > 0) {
      g_autoptr(FlValue) map = fl_value_new_map();
      fl_value_set_string(map, "paths", list);
      fl_method_channel_invoke_method(self->hw_channel, "filesDropped", map,
                                      nullptr, nullptr, nullptr);
    }
    g_strfreev(uris);
  }
  gtk_drag_finish(context, TRUE, FALSE, time);
}

static void hw_method_call_cb(FlMethodChannel* channel,
                              FlMethodCall* call,
                              gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "queryCapabilities") == 0) {
    g_autoptr(FlValue) map = fl_value_new_map();
    fl_value_set_string_take(map, "is_tv", fl_value_new_bool(FALSE));
    fl_value_set_string_take(map, "has_touchscreen", fl_value_new_bool(FALSE));
    fl_value_set_string_take(map, "supports_pip", fl_value_new_bool(FALSE));
    fl_value_set_string_take(map, "supports_hdr10", fl_value_new_bool(FALSE));
    fl_value_set_string_take(map, "supports_hlg", fl_value_new_bool(FALSE));
    fl_value_set_string_take(map, "supports_native_dolby_vision", fl_value_new_bool(FALSE));
    fl_value_set_string_take(map, "supports_atmos_bitstream", fl_value_new_bool(FALSE));
    fl_value_set_string_take(map, "supports_spatial_audio", fl_value_new_bool(FALSE));
    fl_value_set_string_take(map, "max_luminance_nits", fl_value_new_int(400));
    fl_value_set_string_take(map, "refresh_rate_hz", fl_value_new_float(60.0));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
  } else if (strcmp(method, "isFullscreen") == 0) {
    g_autoptr(FlValue) val = fl_value_new_bool(self->is_fullscreen);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
  } else if (strcmp(method, "toggleFullscreen") == 0) {
    if (self->main_window) {
      if (self->is_fullscreen) {
        gtk_window_unfullscreen(self->main_window);
        self->is_fullscreen = FALSE;
      } else {
        gtk_window_fullscreen(self->main_window);
        self->is_fullscreen = TRUE;
      }
    }
    g_autoptr(FlValue) val = fl_value_new_bool(self->is_fullscreen);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
  } else if (strcmp(method, "setFullscreen") == 0) {
    gboolean enable = FALSE;
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* v = fl_value_lookup_string(args, "enabled");
      if (v && fl_value_get_type(v) == FL_VALUE_TYPE_BOOL) {
        enable = fl_value_get_bool(v);
      }
    }
    if (self->main_window) {
      if (enable) gtk_window_fullscreen(self->main_window);
      else gtk_window_unfullscreen(self->main_window);
      self->is_fullscreen = enable;
    }
    g_autoptr(FlValue) val = fl_value_new_bool(self->is_fullscreen);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
  } else if (strcmp(method, "setAlwaysOnTop") == 0) {
    gboolean enable = FALSE;
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* v = fl_value_lookup_string(args, "enabled");
      if (v && fl_value_get_type(v) == FL_VALUE_TYPE_BOOL) {
        enable = fl_value_get_bool(v);
      }
    }
    if (self->main_window) {
      gtk_window_set_keep_above(self->main_window, enable);
    }
    g_autoptr(FlValue) val = fl_value_new_bool(enable);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
  } else if (strcmp(method, "setKeepScreenOn") == 0) {
    gboolean enable = FALSE;
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* v = fl_value_lookup_string(args, "enabled");
      if (v && fl_value_get_type(v) == FL_VALUE_TYPE_BOOL) {
        enable = fl_value_get_bool(v);
      }
    }
    if (enable && self->inhibit_cookie == 0 && self->main_window) {
      self->inhibit_cookie = gtk_application_inhibit(
          GTK_APPLICATION(self), self->main_window,
          GTK_APPLICATION_INHIBIT_IDLE, "Vedro active video playback");
    } else if (!enable && self->inhibit_cookie != 0) {
      gtk_application_uninhibit(GTK_APPLICATION(self), self->inhibit_cookie);
      self->inhibit_cookie = 0;
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "pickFiles") == 0) {
    gboolean allow_dir = FALSE;
    gboolean allow_multi = FALSE;
    const gchar* title = "选择文件";
    FlValue* ext_val = nullptr;
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* v = fl_value_lookup_string(args, "allow_directory");
      if (v && fl_value_get_type(v) == FL_VALUE_TYPE_BOOL) allow_dir = fl_value_get_bool(v);
      v = fl_value_lookup_string(args, "allow_multiple");
      if (v && fl_value_get_type(v) == FL_VALUE_TYPE_BOOL) allow_multi = fl_value_get_bool(v);
      v = fl_value_lookup_string(args, "title");
      if (v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING) title = fl_value_get_string(v);
      ext_val = fl_value_lookup_string(args, "extensions");
    }
    gboolean has_exts = ext_val && fl_value_get_type(ext_val) == FL_VALUE_TYPE_LIST &&
                        fl_value_get_length(ext_val) > 0;
    GtkFileChooserAction action = (allow_dir && !has_exts)
                                      ? GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER
                                      : GTK_FILE_CHOOSER_ACTION_OPEN;
    GtkFileChooserNative* native = gtk_file_chooser_native_new(
        title, self->main_window, action, "_打开", "_取消");
    if (allow_multi && action == GTK_FILE_CHOOSER_ACTION_OPEN) {
      gtk_file_chooser_set_select_multiple(GTK_FILE_CHOOSER(native), TRUE);
    }
    if (has_exts && action == GTK_FILE_CHOOSER_ACTION_OPEN) {
      GtkFileFilter* filter = gtk_file_filter_new();
      gtk_file_filter_set_name(filter, "Supported Files");
      size_t n = fl_value_get_length(ext_val);
      for (size_t i = 0; i < n; ++i) {
        FlValue* item = fl_value_get_list_value(ext_val, i);
        if (item && fl_value_get_type(item) == FL_VALUE_TYPE_STRING) {
          g_autofree gchar* pat = g_strdup_printf("*.%s", fl_value_get_string(item));
          gtk_file_filter_add_pattern(filter, pat);
        }
      }
      gtk_file_chooser_add_filter(GTK_FILE_CHOOSER(native), filter);
      GtkFileFilter* all_filter = gtk_file_filter_new();
      gtk_file_filter_set_name(all_filter, "All Files");
      gtk_file_filter_add_pattern(all_filter, "*");
      gtk_file_chooser_add_filter(GTK_FILE_CHOOSER(native), all_filter);
    }
    g_autoptr(FlValue) out_list = fl_value_new_list();
    if (gtk_native_dialog_run(GTK_NATIVE_DIALOG(native)) == GTK_RESPONSE_ACCEPT) {
      GSList* files = gtk_file_chooser_get_filenames(GTK_FILE_CHOOSER(native));
      for (GSList* it = files; it != nullptr; it = it->next) {
        gchar* fname = static_cast<gchar*>(it->data);
        if (fname && *fname) {
          fl_value_append_take(out_list, fl_value_new_string(fname));
        }
        g_free(fname);
      }
      g_slist_free(files);
    }
    g_object_unref(native);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(out_list));
  } else if (strcmp(method, "saveScreenshotToGallery") == 0) {
    g_autofree gchar* saved_path = nullptr;
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* bv = fl_value_lookup_string(args, "bytes");
      FlValue* nv = fl_value_lookup_string(args, "file_name");
      const gchar* fname = (nv && fl_value_get_type(nv) == FL_VALUE_TYPE_STRING)
                               ? fl_value_get_string(nv)
                               : "vedro_screenshot.png";
      if (bv && fl_value_get_type(bv) == FL_VALUE_TYPE_UINT8_LIST) {
        const gchar* pics = g_get_user_special_dir(G_USER_DIRECTORY_PICTURES);
        if (!pics) pics = g_get_home_dir();
        g_autofree gchar* dir = g_build_filename(pics, "Vedro", nullptr);
        g_mkdir_with_parents(dir, 0755);
        g_autofree gchar* base = g_path_get_basename(fname);
        g_autofree gchar* dest = g_build_filename(dir, base, nullptr);
        if (g_file_set_contents(dest,
                                reinterpret_cast<const gchar*>(fl_value_get_uint8_list(bv)),
                                static_cast<gssize>(fl_value_get_length(bv)),
                                nullptr)) {
          saved_path = g_strdup(dest);
        }
      }
    }
    g_autoptr(FlValue) val = saved_path ? fl_value_new_string(saved_path) : fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
  } else if (strcmp(method, "openUrl") == 0) {
    gboolean ok = FALSE;
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* v = fl_value_lookup_string(args, "url");
      if (v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING) {
        const gchar* url = fl_value_get_string(v);
        if (is_allowed_http_url(url)) {
          ok = gtk_show_uri_on_window(self->main_window, url, GDK_CURRENT_TIME, nullptr);
        }
      }
    }
    g_autoptr(FlValue) val = fl_value_new_bool(ok);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
  } else if (strcmp(method, "enterPiP") == 0) {
    g_autoptr(FlValue) val = fl_value_new_bool(FALSE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
  } else if (strcmp(method, "installUpdatePackage") == 0) {
    gboolean ok = FALSE;
    const gchar* err_msg = "无法打开更新包";
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* pv = fl_value_lookup_string(args, "path");
      if (pv && fl_value_get_type(pv) == FL_VALUE_TYPE_STRING) {
        const gchar* path = fl_value_get_string(pv);
        if (path && *path && g_file_test(path, G_FILE_TEST_IS_REGULAR)) {
          g_autofree gchar* parent = g_path_get_dirname(path);
          g_autofree gchar* uri = g_filename_to_uri(parent, nullptr, nullptr);
          if (uri) {
            ok = gtk_show_uri_on_window(self->main_window, uri, GDK_CURRENT_TIME, nullptr);
          }
        }
      }
    }
    g_autoptr(FlValue) map = fl_value_new_map();
    fl_value_set_string_take(map, "ok", fl_value_new_bool(ok));
    if (!ok) {
      fl_value_set_string_take(map, "message", fl_value_new_string(err_msg));
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(call, response, nullptr);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->main_window = window;
  g_signal_connect(window, "destroy", G_CALLBACK(on_main_window_destroy), self);
  g_signal_connect(window, "window-state-event", G_CALLBACK(on_window_state_event), self);
  gtk_window_set_default_size(window, 1280, 720);

  if (GtkSettings* settings = gtk_settings_get_default()) {
    g_object_set(settings, "gtk-application-prefer-dark-theme", TRUE, nullptr);
  }

  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (wm_name && g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Vedro");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  }

  gtk_window_set_title(window, "Vedro");

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#0b0b0d");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  static const GtkTargetEntry drop_targets[] = {
      {const_cast<gchar*>("text/uri-list"), 0, 0},
  };
  gtk_drag_dest_set(GTK_WIDGET(window), GTK_DEST_DEFAULT_ALL, drop_targets, 1,
                    GDK_ACTION_COPY);
  g_signal_connect(window, "drag-data-received",
                   G_CALLBACK(on_drag_data_received), self);

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  if (self->hw_channel) {
    fl_method_channel_set_method_call_handler(self->hw_channel, nullptr, nullptr, nullptr);
    g_clear_object(&self->hw_channel);
  }
  FlEngine* engine = fl_view_get_engine(view);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->hw_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine),
      "com.vedro.player/hardware",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->hw_channel, hw_method_call_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

static void my_application_shutdown(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->inhibit_cookie != 0) {
    gtk_application_uninhibit(GTK_APPLICATION(self), self->inhibit_cookie);
    self->inhibit_cookie = 0;
  }
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  if (self->hw_channel) {
    fl_method_channel_set_method_call_handler(self->hw_channel, nullptr, nullptr, nullptr);
    g_clear_object(&self->hw_channel);
  }
  self->main_window = nullptr;
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->main_window = nullptr;
  self->is_fullscreen = FALSE;
  self->inhibit_cookie = 0;
  self->hw_channel = nullptr;
}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
