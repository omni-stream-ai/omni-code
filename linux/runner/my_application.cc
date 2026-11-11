#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Native WebViews take GTK focus independently of Flutter's FocusNode tree.
// Return keyboard input to FlView when a native child is hidden, and when the
// user clicks Flutter content again.
static void window_set_focus_cb(GtkWindow* window, GtkWidget* focused,
                                gpointer user_data) {
  GtkWidget* view = GTK_WIDGET(user_data);
  if (focused == nullptr && gtk_widget_get_mapped(view)) {
    gtk_widget_grab_focus(view);
  }
}

static gboolean flutter_button_press_cb(GtkWidget* view, GdkEventButton* event,
                                        gpointer user_data) {
  gtk_widget_grab_focus(view);
  // Wayland requires the serial and device from the actual pointer press.
  g_object_set_data_full(G_OBJECT(view), "omni-window-pointer",
                         gdk_event_copy(reinterpret_cast<GdkEvent*>(event)),
                         reinterpret_cast<GDestroyNotify>(gdk_event_free));
  return FALSE;
}

static void apply_window_appearance(FlView* view, gboolean dark,
                                     const gchar* background,
                                     const gchar* foreground,
                                     const gchar* border) {
  GtkWidget* widget = GTK_WIDGET(view);
  GtkWindow* window = GTK_WINDOW(gtk_widget_get_toplevel(widget));
  GtkCssProvider* provider = GTK_CSS_PROVIDER(
      g_object_get_data(G_OBJECT(view), "omni-window-style"));
  g_autofree gchar* css = g_strdup_printf(
      "window.omni-window { background-color: %s; color: %s; }"
      "window.omni-window decoration { background-color: %s;"
      " border: 1px solid %s; }"
      ".omni-native-titlebar { min-height: 0; min-width: 0;"
      " padding: 0; margin: 0; border: 0; background: none; box-shadow: none; }",
      background, foreground, background, border);
  gtk_css_provider_load_from_data(provider, css, -1, nullptr);
#ifdef GDK_WINDOWING_X11
  GdkWindow* native_window = gtk_widget_get_window(GTK_WIDGET(window));
  if (native_window != nullptr && GDK_IS_X11_WINDOW(native_window)) {
    g_autofree gchar* variant = g_strdup(dark ? "dark" : "light");
    gdk_x11_window_set_theme_variant(native_window, variant);
  }
#endif
}

static FlValue* window_state_value(gboolean maximized) {
  FlValue* state = fl_value_new_map();
  fl_value_set_string_take(state, "customHeader", fl_value_new_bool(TRUE));
  fl_value_set_string_take(state, "maximized", fl_value_new_bool(maximized));
  return state;
}

static gboolean window_state_cb(GtkWidget* window, GdkEventWindowState* event,
                                 gpointer user_data) {
  FlMethodChannel* channel = FL_METHOD_CHANNEL(
      g_object_get_data(G_OBJECT(user_data), "omni-window-channel"));
  g_autoptr(FlValue) state = window_state_value(
      (event->new_window_state & GDK_WINDOW_STATE_MAXIMIZED) != 0);
  fl_method_channel_invoke_method(channel, "stateChanged", state, nullptr,
                                  nullptr, nullptr);
  return FALSE;
}

static gboolean close_window_cb(gpointer window) {
  gtk_window_close(GTK_WINDOW(window));
  return G_SOURCE_REMOVE;
}

static void window_method_call_cb(FlMethodChannel* channel,
                                   FlMethodCall* method_call, gpointer user_data) {
  FlView* view = FL_VIEW(user_data);
  GtkWindow* window = GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  const gchar* method = fl_method_call_get_name(method_call);
  if (g_strcmp0(method, "getState") == 0) {
    g_autoptr(FlValue) state = window_state_value(gtk_window_is_maximized(window));
    g_autoptr(FlMethodSuccessResponse) response = fl_method_success_response_new(state);
    fl_method_call_respond(method_call, FL_METHOD_RESPONSE(response), nullptr);
    return;
  }
  if (g_strcmp0(method, "minimize") == 0 ||
      g_strcmp0(method, "toggleMaximize") == 0 ||
      g_strcmp0(method, "close") == 0 ||
      g_strcmp0(method, "startDragging") == 0) {
    if (g_strcmp0(method, "minimize") == 0) {
      gtk_window_iconify(window);
    } else if (g_strcmp0(method, "toggleMaximize") == 0) {
      if (gtk_window_is_maximized(window)) {
        gtk_window_unmaximize(window);
      } else {
        gtk_window_maximize(window);
      }
    } else if (g_strcmp0(method, "close") == 0) {
      // Let the method reply finish before destroying the engine and channel.
      g_idle_add_full(G_PRIORITY_DEFAULT_IDLE, close_window_cb,
                      g_object_ref(window), g_object_unref);
    } else {
      const GdkEvent* press = static_cast<GdkEvent*>(
          g_object_get_data(G_OBJECT(view), "omni-window-pointer"));
      if (press != nullptr) {
        gtk_window_begin_move_drag(window, press->button.button,
                                    press->button.x_root, press->button.y_root,
                                    press->button.time);
      }
    }
    g_autoptr(FlMethodSuccessResponse) response = fl_method_success_response_new(nullptr);
    fl_method_call_respond(method_call, FL_METHOD_RESPONSE(response), nullptr);
    return;
  }
  if (g_strcmp0(method, "setAppearance") != 0) {
    g_autoptr(FlMethodNotImplementedResponse) response =
        fl_method_not_implemented_response_new();
    fl_method_call_respond(method_call, FL_METHOD_RESPONSE(response), nullptr);
    return;
  }
  FlValue* args = fl_method_call_get_args(method_call);
  FlValue* dark = nullptr;
  const gchar* colors[3] = {};
  const gchar* keys[] = {"background", "foreground", "border"};
  gboolean valid =
      args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP;
  if (valid) {
    dark = fl_value_lookup_string(args, "dark");
    valid = dark != nullptr && fl_value_get_type(dark) == FL_VALUE_TYPE_BOOL;
  }
  for (int i = 0; valid && i < 3; i++) {
    FlValue* color = fl_value_lookup_string(args, keys[i]);
    valid = color != nullptr && fl_value_get_type(color) == FL_VALUE_TYPE_STRING;
    if (valid) {
      colors[i] = fl_value_get_string(color);
      GdkRGBA parsed;
      valid = gdk_rgba_parse(&parsed, colors[i]);
    }
  }
  if (!valid) {
    g_autoptr(FlMethodErrorResponse) response = fl_method_error_response_new(
        "invalid_appearance", "Expected a theme and three valid colors", nullptr);
    fl_method_call_respond(method_call, FL_METHOD_RESPONSE(response), nullptr);
    return;
  }
  apply_window_appearance(FL_VIEW(user_data), fl_value_get_bool(dark),
                           colors[0], colors[1], colors[2]);
  g_autoptr(FlMethodSuccessResponse) response =
      fl_method_success_response_new(nullptr);
  fl_method_call_respond(method_call, FL_METHOD_RESPONSE(response), nullptr);
}

static void remove_window_style_cb(GtkWidget* view, gpointer provider) {
  gtk_style_context_remove_provider_for_screen(
      gtk_widget_get_screen(view), GTK_STYLE_PROVIDER(provider));
}

static void setup_window_appearance(FlView* view) {
  GtkCssProvider* provider = gtk_css_provider_new();
  g_object_set_data_full(G_OBJECT(view), "omni-window-style", provider,
                         g_object_unref);
  gtk_style_context_add_provider_for_screen(
      gtk_widget_get_screen(GTK_WIDGET(view)), GTK_STYLE_PROVIDER(provider),
      GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  g_signal_connect(view, "destroy", G_CALLBACK(remove_window_style_cb), provider);
  apply_window_appearance(view, TRUE, "#17181d", "#9aa9b8", "#27313c");

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "omni_code/window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, window_method_call_cb, view,
                                            nullptr);
  g_object_set_data_full(G_OBJECT(view), "omni-window-channel", channel,
                         g_object_unref);
  g_signal_connect_object(gtk_widget_get_toplevel(GTK_WIDGET(view)),
                           "window-state-event", G_CALLBACK(window_state_cb),
                           view, static_cast<GConnectFlags>(0));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  gtk_window_set_title(window, "Omni Code");

  // Keep GTK's client-side resize borders, with all header content in Flutter.
  // Configure this before realizing FlView so its GL surface stays intact.
  gtk_style_context_add_class(gtk_widget_get_style_context(GTK_WIDGET(window)),
                              "omni-window");
  GtkWidget* titlebar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_style_context_add_class(gtk_widget_get_style_context(titlebar),
                              "omni-native-titlebar");
  gtk_window_set_titlebar(window, titlebar);
  gtk_widget_show(titlebar);

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  // Prepare the WebView plugin's overlay before realizing FlView. Reparenting
  // an already-realized Flutter view destroys its GL surface and can leave the
  // entire application black when the first WebView is created.
  GtkWidget* overlay = gtk_overlay_new();
  gtk_widget_set_hexpand(overlay, TRUE);
  gtk_widget_set_vexpand(overlay, TRUE);
  gtk_container_add(GTK_CONTAINER(window), overlay);
  gtk_container_add(GTK_CONTAINER(overlay), GTK_WIDGET(view));
  setup_window_appearance(view);
  g_signal_connect_after(window, "set-focus", G_CALLBACK(window_set_focus_cb),
                         view);
  g_signal_connect(view, "button-press-event",
                   G_CALLBACK(flutter_button_press_cb), nullptr);
  gtk_widget_show(overlay);
  gtk_widget_show(GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
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

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
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

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
