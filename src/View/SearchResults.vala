
namespace Marlin.View
{
    public class SearchResults : Gtk.Window
    {
        class Match : Object
        {
            public string name { get; construct; }
            public string mime { get; construct; }
            public string path_string { get; construct; }
            public Icon icon { get; construct; }
            public File file { get; construct; }

            public Match (FileInfo info, string path_string, File parent)
            {
                Object (name: info.get_name (),
                        mime: info.get_content_type (),
                        icon: info.get_icon (),
                        path_string: path_string,
                        file: parent.resolve_relative_path (info.get_name ()));
            }

            public Match.from_bookmark (Bookmark bookmark)
            {
                Object (name: bookmark.label,
                        mime: "inode/directory",
                        icon: bookmark.get_icon (),
                        path_string: "",
                        file: bookmark.get_location ());
            }
        }

        const int MAX_RESULTS = 10;
        const int MAX_DEPTH = 5;

        public signal void file_selected (File file);

        public Gtk.Entry entry { get; construct; }
        public bool working { get; private set; default = false; }

        File current_root;
        Gee.Queue<File> directory_queue;
        Gee.LinkedList<Match> results;
        ulong waiting_handler;

        Cancellable? current_operation = null;
        Cancellable? file_search_operation = null;

        Zeitgeist.Index zg_index;
        GenericArray<Zeitgeist.Event> templates;

        int display_count;

        bool local_search_finished = false;
        bool global_search_finished = false;

        bool is_grabbing = false;
        Gdk.Device? device = null;

        Gtk.TreeIter local_results;
        Gtk.TreeIter global_results;
        Gtk.TreeIter bookmark_results;
        Gtk.TreeView view;
        Gtk.TreeStore list;

        public SearchResults (Gtk.Entry entry)
        {
            Object (entry: entry,
                    resizable: false,
                    type_hint: Gdk.WindowTypeHint.COMBO,
                    type: Gtk.WindowType.POPUP);
        }

        construct
        {
            var template = new Zeitgeist.Event ();

            var template_subject  = new Zeitgeist.Subject ();
            template_subject.manifestation = Zeitgeist.NFO.FILE_DATA_OBJECT;
            template.add_subject (template_subject);

            templates = new GenericArray<Zeitgeist.Event> ();
            templates.add (template);

            zg_index = new Zeitgeist.Index ();

            var frame = new Gtk.Frame (null);
            frame.shadow_type = Gtk.ShadowType.ETCHED_IN;

            view = new Gtk.TreeView ();
            view.headers_visible = false;
            view.show_expanders = false;

            Gtk.CellRenderer cell;
            var column = new Gtk.TreeViewColumn ();

            cell= new Gtk.CellRendererPixbuf ();
            column.pack_start (cell, false);
            column.set_attributes (cell, "pixbuf", 1, "visible", 4);

            cell = new Gtk.CellRendererText ();
            column.pack_start (cell, true);
            column.set_attributes (cell, "text", 0);

            var cell_path = new Gtk.CellRendererText ();
            cell_path.xalign = 1.0f;
            cell_path.ellipsize = Pango.EllipsizeMode.MIDDLE;
            cell_path.alignment = Pango.Alignment.RIGHT;
            column.pack_start (cell_path, false);
            column.set_attributes (cell_path, "markup", 2);

            view.append_column (column);

            list = new Gtk.TreeStore (5, typeof (string), typeof (Gdk.Pixbuf),
                typeof (string), typeof (File), typeof (bool));
            view.model = list;

            list.append (out local_results, null);
            list.@set (local_results, 0, _("In this folder:"));
            list.append (out global_results, null);
            list.@set (global_results, 0, _("Everywhere else:"));
            list.append (out bookmark_results, null);
            list.@set (bookmark_results, 0, _("Bookmarks:"));

            frame.add (view);
            add (frame);

            entry.focus_out_event.connect (() => {
                popdown ();
                return false;
            });

            button_press_event.connect (() => {
                entry.text = "";
                popdown ();
                return false;
            });

            view.button_press_event.connect ((e) => {
                Gtk.TreePath path;
                Gtk.TreeIter iter;

                view.get_path_at_pos ((int) e.x, (int) e.y, out path, null, null, null);

                if (path != null) {
                    list.get_iter (out iter, path);
                    accept (iter);
                }

                popdown ();

                return true;
            });

            key_release_event.connect (key_event);
            key_press_event.connect (key_event);

            entry.key_press_event.connect (entry_key_press);
        }

        bool entry_key_press (Gdk.EventKey event)
        {
            if (!get_mapped ())
                return false;

            switch (event.keyval) {
                case Gdk.Key.Escape:
                case Gdk.Key.Left:
                case Gdk.Key.Right:
                case Gdk.Key.KP_Left:
                case Gdk.Key.KP_Right:
                    popdown ();
                    return true;
                case Gdk.Key.Return:
                case Gdk.Key.KP_Enter:
                case Gdk.Key.ISO_Enter:
                    accept ();
                    popdown ();
                    return true;
                case Gdk.Key.Up:
                case Gdk.Key.Down:
                    if (list_empty ()) {
                        Gdk.beep ();
                        return true;
                    }

                    var down = event.keyval == Gdk.Key.Down;

                    if (view.get_selection ().count_selected_rows () < 1) {
                        if (down)
                            select_first ();
                        else
                            select_last ();
                        return true;
                    }

                    Gtk.TreePath path;
                    Gtk.TreeIter iter, parent;

                    view.get_cursor (out path, null);
                    list.get_iter (out iter, path);

                    if ((!down && !list.iter_previous (ref iter))
                        || (down && !list.iter_next (ref iter))) {

                        list.get_iter (out iter, path);
                        list.iter_parent (out parent, iter);

                        var found = false;
                        while ((!down && list.iter_previous (ref parent))
                                || (down && list.iter_next (ref parent))) {

                            if (!list.iter_has_child (parent))
                                continue;

                            list.iter_nth_child (out iter, parent, down ? 0 : list.iter_n_children (parent) - 1);
                            found = true;
                            break;
                        }

                        if (!found) {
                            if (down)
                                select_first ();
                            else
                                select_last ();

                            return true;
                        }
                    }

                    path = list.get_path (iter);
                    view.set_cursor (path, null, false);

                    return true;
            }

            return false;
        }

        bool key_event (Gdk.EventKey event)
        {
            if (!get_mapped ())
                return false;

            entry.event (event);

            return true;
        }

        void select_first ()
        {
            Gtk.TreeIter iter;
            list.get_iter_first (out iter);

            do {
                if (!list.iter_has_child (iter))
                    continue;

                var path = list.get_path (iter);
                path.append_index (0);

                view.set_cursor (path, null, false);
                break;
            } while (list.iter_next (ref iter));
        }

        void select_last ()
        {
            Gtk.TreeIter iter;
            list.iter_nth_child (out iter, null, list.iter_n_children (null) - 1);

            do {
                if (!list.iter_has_child (iter))
                    continue;

                var path = list.get_path (iter);
                path.append_index (list.iter_n_children (iter) - 1);

                view.set_cursor (path, null, false);
                break;
            } while (list.iter_previous (ref iter));
        }

        bool list_empty ()
        {
            Gtk.TreeIter iter;
            for (var valid = list.get_iter_first (out iter); valid; valid = list.iter_next (ref iter)) {
                if (list.iter_has_child (iter))
                    return false;
            }

            return true;
        }

        void resize_popup ()
        {
            var entry_window = entry.get_window ();
            if (entry_window == null)
                return;

            int x, y;
            Gtk.Allocation entry_alloc;

            entry_window.get_origin (out x, out y);
            entry.get_allocation (out entry_alloc);

            x += entry_alloc.x;
            y += entry_alloc.y;

            var screen = entry.get_screen ();
            var monitor = screen.get_monitor_at_window (entry_window);
            var workarea = screen.get_monitor_workarea (monitor);

            set_size_request (int.min (entry_alloc.width, workarea.width), -1);

            if (x < workarea.x)
                x = workarea.x;
            else if (x + width_request > workarea.x + workarea.width)
                x = workarea.x + workarea.width - width_request;

            y += entry_alloc.height;

            move (x, y);
        }

        void popup ()
        {
            if (get_mapped ()
                || !entry.get_mapped ()
                || !entry.has_focus
                || is_grabbing)
                return;

            resize_popup ();

            var toplevel = entry.get_toplevel ();
            if (toplevel is Gtk.Window)
                ((Gtk.Window) toplevel).get_group ().add_window (this);

            set_screen (entry.get_screen ());

            show_all ();

            device = Gtk.get_current_event_device ();
            if (device != null && device.input_source == Gdk.InputSource.KEYBOARD)
                device = device.associated_device;

            if (device != null) {
                Gtk.device_grab_add (this, device, true);
                device.grab (get_window (), Gdk.GrabOwnership.WINDOW, true, Gdk.EventMask.BUTTON_PRESS_MASK
                    | Gdk.EventMask.BUTTON_RELEASE_MASK
                    | Gdk.EventMask.POINTER_MOTION_MASK,
                    null, Gdk.CURRENT_TIME);

                is_grabbing = true;
            }
        }

        void popdown ()
        {
            entry.reset_im_context ();

            if (is_grabbing && device != null) {
                device.ungrab (Gdk.CURRENT_TIME);
                Gtk.device_grab_remove (this, device);

                is_grabbing = false;
            }

            hide ();
        }

        void add_results (Gee.List<Match> new_results, Gtk.TreeIter parent)
        {
            foreach (var match in new_results) {
                Gdk.Pixbuf? pixbuf = null;
                var icon_info = Gtk.IconTheme.get_default ().lookup_by_gicon (match.icon, 16, 0);
                if (icon_info != null) {
                    try {
                        pixbuf = icon_info.load_icon ();
                    } catch (Error e) {}
                }

                var location = "\t<span style=\"italic\">%s</span>".printf (
                    Markup.escape_text (match.path_string));

                Gtk.TreeIter iter;
                list.append (out iter, parent);
                list.@set (iter, 0, match.name, 1, pixbuf, 2, location, 3, match.file, 4, true);

                view.expand_all ();
            }
        }

        void accept (Gtk.TreeIter? accepted = null)
        {
            if (list_empty ()) {
                Gdk.beep ();
                return;
            }

            if (accepted == null) {
                Gtk.TreePath path;
                view.get_cursor (out path, null);
                list.get_iter (out accepted, path);
            }

            File file;
            list.@get (accepted, 3, out file);

            file_selected (file);
        }

        public void clear ()
        {
            Gtk.TreeIter parent, iter;
            for (var valid = list.get_iter_first (out parent); valid; valid = list.iter_next (ref parent)) {
                if (!list.iter_nth_child (out iter, parent, 0))
                    continue;

                while (list.remove (ref iter));
            }
        }

        public void search (string term, File folder)
        {
            if (!current_operation.is_cancelled ())
                current_operation.cancel ();

            if (working) {
                if (waiting_handler != 0)
                    SignalHandler.disconnect (this, waiting_handler);

                waiting_handler = notify["working"].connect (() => {
                    SignalHandler.disconnect (this, waiting_handler);
                    waiting_handler = 0;
                    search (term, folder);
                });
                return;
            }

            if (term.strip () == "") {
                if (visible)
                    popdown ();

                clear ();
                return;
            }

            popup ();

            var include_hidden = GOF.Preferences.get_default ().pref_show_hidden_files;

            display_count = 0;
            directory_queue = new Gee.LinkedList<File> ();
            results = new Gee.LinkedList<Match> ();
            current_root = folder;

            current_operation = new Cancellable ();
            file_search_operation = new Cancellable ();

            current_operation.cancelled.connect (file_search_operation.cancel);

            clear ();

            working = true;

            directory_queue.add (folder);

            new Thread<void*> (null, () => {
                while (!file_search_operation.is_cancelled () && directory_queue.size > 0) {
                    visit (term.normalize ().casefold (), include_hidden, file_search_operation);
                }

                global_search_finished = true;
                Idle.add (send_search_finished);

                return null;
            });

            get_zg_results.begin (term);

            var bookmarks_matched = new Gee.LinkedList<Match> ();
            foreach (var bookmark in BookmarkList.get_instance ().list) {
                if (term_matches (term, bookmark.label)) {
                    bookmarks_matched.add (new Match.from_bookmark (bookmark));
                }
            }

            add_results (bookmarks_matched, bookmark_results);
        }

        bool send_search_finished ()
        {
            if (!local_search_finished || !global_search_finished)
                return false;

            working = false;

            select_first ();
            if (list_empty ())
                view.get_selection ().unselect_all ();

            return false;
        }

        string ATTRIBUTES = FileAttribute.STANDARD_NAME + "," +
                            FileAttribute.STANDARD_CONTENT_TYPE + "," +
                            FileAttribute.STANDARD_IS_HIDDEN + "," +
                            FileAttribute.STANDARD_TYPE + "," +
                            FileAttribute.STANDARD_ICON;

        void visit (string term, bool include_hidden, Cancellable cancel)
        {
            FileEnumerator enumerator;

            var folder = directory_queue.poll ();
            if (folder == null)
                return;

            var depth = 0;

            File f = folder;
            var path_string = "";
            while (!f.equal (current_root)) {
                path_string = f.get_basename () + (path_string == "" ? "" : " > " + path_string);
                f = f.get_parent ();
                depth++;
            }

            if (depth > MAX_DEPTH)
                return;

            try {
                enumerator = folder.enumerate_children (ATTRIBUTES, 0, cancel);
            } catch (Error e) {
                return;
            }

            var new_results = new Gee.LinkedList<Match> ();

            FileInfo info = null;
            try {
                while (!cancel.is_cancelled () && (info = enumerator.next_file (null)) != null) {
                    if (info.get_is_hidden () && !include_hidden)
                        continue;

                    if (info.get_file_type () == FileType.DIRECTORY) {
                        directory_queue.add (folder.resolve_relative_path (info.get_name ()));
                    }

                    if (term_matches (term, info.get_name ()))
                        new_results.add (new Match (info, path_string, folder));
                }
            } catch (Error e) {}

            if (!cancel.is_cancelled ()) {
                var new_count = display_count + new_results.size;
                if (new_count > MAX_RESULTS) {
                    cancel.cancel ();

                    var num_ok = MAX_RESULTS - display_count;
                    if (num_ok < new_results.size) {
                        var count = 0;
                        var it = new_results.iterator ();
                        while (it.next ()) {
                            count++;
                            if (count > num_ok)
                                it.remove ();
                        }
                    } else if (num_ok == 0)
                        return;

                    display_count = MAX_RESULTS;
                } else
                    display_count = new_count;

                // use a closure here to get vala to pass the userdata that we actually want
                Idle.add (() => {
                    add_results (new_results, local_results);
                    return false;
                });
            }
        }

        async void get_zg_results (string term)
        {
            Zeitgeist.ResultSet results;
            try {
                results = yield zg_index.search (term,
                                                 new Zeitgeist.TimeRange.anytime (),
                                                 templates,
                                                 0, // offset
                                                 MAX_RESULTS,
                                                 Zeitgeist.ResultType.MOST_POPULAR_SUBJECTS,
                                                 current_operation);
            } catch (IOError.CANCELLED e) {
                return;
            } catch (Error e) {
                warning ("Fetching results for term '%s' from zeitgeist failed: %s", term, e.message);
                return;
            }

            var matches = new Gee.LinkedList<Match> ();
            var home = File.new_for_path (Environment.get_home_dir ());
            while (results.has_next () && !current_operation.is_cancelled ()) {
                var result = results.next_value ();
                foreach (var subject in result.subjects.data) {
                    try {
                        var file = File.new_for_uri (subject.uri);
                        var path_string = "";
                        var parent = file;
                        while ((parent = parent.get_parent ()) != null) {
                            if (parent.equal (current_root))
                                break;

                            if (parent.equal (home)) {
                                path_string = "~ > " + path_string;
                                break;
                            }

                            if (path_string == "")
                                path_string = parent.get_basename ();
                            else
                                path_string = parent.get_basename () + " > " + path_string;
                        }

                        var info = yield file.query_info_async (ATTRIBUTES, 0, Priority.DEFAULT, current_operation);
                        matches.add (new Match (info, path_string, file.get_parent ()));
                    } catch (Error e) {}
                }
            }

            if (!current_operation.is_cancelled ())
                add_results (matches, global_results);

            local_search_finished = true;
            Idle.add (send_search_finished);
        }

        bool term_matches (string term, string name)
        {
            // TODO improve.

            // term is assumed to be down
            var res = name.normalize ().casefold ().contains (term);
            return res;
        }
    }
}

