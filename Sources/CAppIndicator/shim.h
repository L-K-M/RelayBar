#ifndef RELAYBAR_C_APP_INDICATOR_SHIM_H
#define RELAYBAR_C_APP_INDICATOR_SHIM_H

#include <gtk/gtk.h>
#include <libayatana-appindicator/app-indicator.h>

/*
 * Thin static-inline helpers so Swift never names libappindicator C enum
 * enumerators or GTK casting macros, whose clang-imported spellings vary by
 * toolchain. Everything here is call-shaped and side-effect free beyond the
 * wrapped call.
 */

typedef void (*RelaybarActivateCallback)(GtkWidget *item, gpointer user_data);
typedef gboolean (*RelaybarSourceFunc)(gpointer user_data);

static inline AppIndicator *relaybar_indicator_new(const char *id,
                                                   const char *icon_name) {
    return app_indicator_new(id, icon_name,
                             APP_INDICATOR_CATEGORY_APPLICATION_STATUS);
}

static inline void relaybar_indicator_set_active(AppIndicator *indicator) {
    app_indicator_set_status(indicator, APP_INDICATOR_STATUS_ACTIVE);
}

static inline void relaybar_indicator_set_title(AppIndicator *indicator,
                                                const char *title) {
    app_indicator_set_title(indicator, title);
}

static inline void relaybar_indicator_set_icon(AppIndicator *indicator,
                                               const char *icon_name) {
    app_indicator_set_icon_name(indicator, icon_name);
}

static inline void relaybar_indicator_set_menu(AppIndicator *indicator,
                                               GtkMenuShell *shell) {
    app_indicator_set_menu(indicator, GTK_MENU(shell));
}

static inline GtkWidget *relaybar_menu_new(void) {
    return gtk_menu_new();
}

static inline GtkWidget *relaybar_check_item_new(const char *label,
                                                 int checked) {
    GtkCheckMenuItem *item = GTK_CHECK_MENU_ITEM(gtk_check_menu_item_new_with_label(label));
    gtk_check_menu_item_set_active(item, checked ? TRUE : FALSE);
    return GTK_WIDGET(item);
}

static inline GtkWidget *relaybar_plain_item_new(const char *label) {
    return gtk_menu_item_new_with_label(label);
}

static inline GtkWidget *relaybar_separator_new(void) {
    return gtk_separator_menu_item_new();
}

static inline void relaybar_menu_append(GtkWidget *shell, GtkWidget *item) {
    gtk_menu_shell_append(GTK_MENU_SHELL(shell), item);
}

static inline void relaybar_clear_menu(GtkWidget *shell) {
    gtk_container_foreach(GTK_CONTAINER(shell),
                          (GtkCallback)gtk_widget_destroy, NULL);
}

static inline void relaybar_widget_show_all(GtkWidget *widget) {
    gtk_widget_show_all(widget);
}

static inline void relaybar_item_set_sensitive(GtkWidget *item, int sensitive) {
    gtk_widget_set_sensitive(item, sensitive ? TRUE : FALSE);
}

static inline gulong relaybar_connect_activate(GtkWidget *item,
                                               RelaybarActivateCallback cb,
                                               gpointer user_data) {
    return g_signal_connect_data(item, "activate", G_CALLBACK(cb), user_data,
                                 NULL, (GConnectFlags)0);
}

static inline guint relaybar_idle_add(RelaybarSourceFunc fn,
                                      gpointer user_data) {
    return g_idle_add_full(G_PRIORITY_DEFAULT_IDLE, fn, user_data, NULL);
}

static inline void relaybar_gtk_init(void) {
    int argc = 0;
    char **argv = NULL;
    gtk_init(&argc, &argv);
}

static inline GMainLoop *relaybar_main_loop_new(void) {
    return g_main_loop_new(NULL, FALSE);
}

static inline void relaybar_main_loop_run(GMainLoop *loop) {
    g_main_loop_run(loop);
}

static inline void relaybar_main_loop_quit(GMainLoop *loop) {
    g_main_loop_quit(loop);
}

#endif /* RELAYBAR_C_APP_INDICATOR_SHIM_H */
