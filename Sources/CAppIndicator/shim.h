#ifndef RELAYBAR_C_APP_INDICATOR_SHIM_H
#define RELAYBAR_C_APP_INDICATOR_SHIM_H

#include <gtk/gtk.h>
#include <libayatana-appindicator/app-indicator.h>

/*
 * Thin static-inline helpers so Swift never names libappindicator C enum
 * enumerators or GTK casting macros, whose clang-imported spellings vary by
 * toolchain. The surface speaks only in char* and void*: GTK opaque structs
 * import into Swift as typed pointers, and keeping every handle untyped on
 * the Swift side makes the ABI independent of importer details.
 */

typedef void (*RelaybarActivateCallback)(void *item, void *user_data);
typedef int (*RelaybarSourceFunc)(void *user_data);

static inline void *relaybar_indicator_new(const char *id,
                                           const char *icon_name) {
    return (void *)app_indicator_new(id, icon_name,
                                     APP_INDICATOR_CATEGORY_APPLICATION_STATUS);
}

static inline void relaybar_indicator_set_active(void *indicator) {
    app_indicator_set_status((AppIndicator *)indicator,
                             APP_INDICATOR_STATUS_ACTIVE);
}

static inline void relaybar_indicator_set_title(void *indicator,
                                                const char *title) {
    app_indicator_set_title((AppIndicator *)indicator, title);
}

static inline void relaybar_indicator_set_menu(void *indicator,
                                               void *shell) {
    app_indicator_set_menu((AppIndicator *)indicator, GTK_MENU(shell));
}

static inline void *relaybar_menu_new(void) {
    return (void *)gtk_menu_new();
}

static inline void *relaybar_check_item_new(const char *label, int checked) {
    GtkCheckMenuItem *item =
        GTK_CHECK_MENU_ITEM(gtk_check_menu_item_new_with_label(label));
    gtk_check_menu_item_set_active(item, checked ? TRUE : FALSE);
    return (void *)GTK_WIDGET(item);
}

static inline void *relaybar_plain_item_new(const char *label) {
    return (void *)gtk_menu_item_new_with_label(label);
}

static inline void *relaybar_separator_new(void) {
    return (void *)gtk_separator_menu_item_new();
}

static inline void relaybar_menu_append(void *shell, void *item) {
    gtk_menu_shell_append(GTK_MENU_SHELL(shell), GTK_WIDGET(item));
}

static inline void relaybar_clear_menu(void *shell) {
    gtk_container_foreach(GTK_CONTAINER(shell),
                          (GtkCallback)gtk_widget_destroy, NULL);
}

static inline void relaybar_widget_show_all(void *widget) {
    gtk_widget_show_all(GTK_WIDGET(widget));
}

static inline void relaybar_item_set_sensitive(void *item, int sensitive) {
    gtk_widget_set_sensitive(GTK_WIDGET(item), sensitive ? TRUE : FALSE);
}

static inline gulong relaybar_connect_activate(void *item,
                                               RelaybarActivateCallback cb,
                                               void *user_data) {
    return g_signal_connect_data(item, "activate", G_CALLBACK(cb), user_data,
                                 NULL, (GConnectFlags)0);
}

static inline guint relaybar_idle_add(RelaybarSourceFunc fn,
                                      void *user_data) {
    return g_idle_add_full(G_PRIORITY_DEFAULT_IDLE,
                           (GSourceFunc)fn, user_data, NULL);
}

static inline void relaybar_gtk_init(void) {
    int argc = 0;
    char **argv = NULL;
    gtk_init(&argc, &argv);
}

static inline void *relaybar_main_loop_new(void) {
    return (void *)g_main_loop_new(NULL, FALSE);
}

static inline void relaybar_main_loop_run(void *loop) {
    g_main_loop_run((GMainLoop *)loop);
}

static inline void relaybar_main_loop_quit(void *loop) {
    g_main_loop_quit((GMainLoop *)loop);
}

#endif /* RELAYBAR_C_APP_INDICATOR_SHIM_H */
