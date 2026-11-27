#include "my_application.h"

#include <cstring>
#include <flutter_linux/flutter_linux.h>

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
  if (!g_str_has_prefix(url, "http://") && !g_str_has_prefix(url, "https://")) {
    return FALSE;
  }
  for (const gchar* p = url; *p; ++p) {
    if (static_cast<unsigned char>(*p) < 0x20) return FALSE;
  }
  return TRUE;
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
  gtk_window_set_default_size(window, 1280, 720);

  if (GtkSettings* settings = gtk_settings_get_default()) {
    g_object_set(settings, "gtk-application-prefer-dark-theme", TRUE, nullptr);
  }

  GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
  gtk_widget_show(GTK_WIDGET(header_bar));
  gtk_header_bar_set_title(header_bar, "Vedro");
  gtk_header_bar_set_show_close_button(header_bar, TRUE);
  gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));

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

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

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
  g_clear_object(&self->hw_channel);
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
