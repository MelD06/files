using Gtk;
using GLib;

public void marlin_toolbar_editor_dialog_show (Marlin.View.Window mvw);

[CCode (cprefix = "", lower_case_cprefix = "", cheader_filename = "marlin-global-preferences.h")]
namespace Preferences {
    public GLib.Settings settings;
    public GLib.Settings marlin_icon_view_settings;
    public GLib.Settings marlin_list_view_settings;
    public GLib.Settings marlin_column_view_settings;
}

namespace FM {
    [CCode (cprefix = "FMDirectory", lower_case_cprefix = "fm_directory_")]
    namespace Directory {
        [CCode (cheader_filename = "fm-directory-view.h")]
        public class View : Gtk.ScrolledWindow {
            public void colorize_selection (int color);
            public signal void sync_selection ();
            public void notify_selection_changed ();
            public unowned List<GOF.File> get_selection ();
            public void merge_menus ();
            public void unmerge_menus ();
            public void zoom_in ();
            public void zoom_out ();
            public void zoom_normal ();
            public unowned List<AppInfo>? get_open_with_apps ();
            public AppInfo? get_default_app ();
            public void select_glib_files (List files);
        }
    }
}
[CCode (cprefix = "GOF", lower_case_cprefix = "gof_")]
namespace GOF {
    [CCode (cprefix = "GOFWindow", lower_case_cprefix = "gof_window_")]
    namespace Window {
        [CCode (cheader_filename = "gof-window-slot.h")]
        public class Slot : GOF.AbstractSlot {
            public Slot (GLib.File f, Gtk.Overlay ctab);
            public void make_icon_view ();
            public void make_list_view ();
            public void make_compact_view ();
            public void add_extra_widget(Gtk.Widget widget);
            public Directory.Async directory;
            public GLib.File location;
            public Widget view_box;
            public signal void active ();
            public signal void inactive ();
        }
    }
}

namespace Marlin {
    [CCode (cheader_filename = "marlin-thumbnailer.h")]
    public class Thumbnailer : Object {
        public static Thumbnailer get();
        public bool queue_file(GOF.File file, int? request, bool large);

    }
    [CCode (cheader_filename = "marlin-bookmark.h")]
    public class Bookmark : Object {
        public File get_location ();
        public string get_name ();
        public bool uri_known_not_to_exist ();
    }
    [CCode (cheader_filename = "marlin-bookmark-list.h")]
    public class BookmarkList : Object {
        public signal void contents_changed ();
        public BookmarkList ();
        public int length ();
        public unowned Bookmark item_at (int index);
    }
    [CCode (cprefix = "MarlinWindow", lower_case_cprefix = "marlin_window_")]
    namespace Window {
        [CCode (cheader_filename = "marlin-window-columns.h")]
        public class Columns : GOF.AbstractSlot {
            //public Columns (GLib.File f, Marlin.View.ViewContainer ctab);
            public Columns (GLib.File f, Gtk.Overlay ctab);
            public void make_view ();
            public GOF.Window.Slot active_slot;
            /*public Directory.Async directory;
            public Widget get_view ();*/
        }
    }
    [CCode (cprefix = "MarlinConnectServer", lower_case_cprefix = "marlin_connect_server_")]
    namespace ConnectServer {
        [CCode (cheader_filename = "marlin-connect-server-dialog.h")]
        public class Dialog : Gtk.Dialog {
            public Dialog (Gtk.Window window);
            public async bool display_location_async (GLib.File location) throws Error;
            public async bool fill_details_async (GLib.MountOperation operation,
                                                  string default_user,
                                                  string default_domain,
                                                  AskPasswordFlags flags);
        }
    }
    
    [CCode (cprefix = "MarlinPlaces", lower_case_cprefix = "marlin_places_")]
    namespace Places {
        [CCode (cheader_filename = "marlin-places-sidebar.h")]
        public class Sidebar : Gtk.ScrolledWindow {
            public Sidebar (Gtk.Widget window);
        }
    }
    [CCode (cprefix = "MarlinClipboard", lower_case_cprefix = "marlin_clipboard_")]
    namespace Clipboard {
        [CCode (cheader_filename = "marlin-clipboard-manager.h")]
        public class Manager : GLib.Object {
            public Manager.get_for_display (Gdk.Display display);
            public bool get_can_paste ();
            public bool has_cutted_files (GOF.File file);
            public void copy_files (GLib.List files);
            public void cut_files (GLib.List files);
            public void paste_files (GLib.File target, Gtk.Widget widget, GLib.List files, GLib.Closure new_file_closure);
        }
    }
    [CCode (cprefix = "MarlinFileOperations", lower_case_cprefix = "marlin_file_operations_")]
    namespace FileOperations {
        [CCode (cheader_filename = "marlin-file-operations.h")]
        public void new_folder(Gtk.Widget? parent_view, Gdk.Point? target_point, File file, void* callback, void* data_callback);
        [CCode (cheader_filename = "marlin-file-operations.h")]
        public void new_folder_with_name(Gtk.Widget? parent_view, Gdk.Point? target_point, File file, string name, void* callback, void* data_callback);
        [CCode (cheader_filename = "marlin-file-operations.h")]
        public void new_folder_with_name_recursive(Gtk.Widget? parent_view, Gdk.Point? target_point, File file, string name, void* callback, void* data_callback);
    }
}