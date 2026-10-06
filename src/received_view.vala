using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Nearby {

    public class ReceivedView : Box {
        private NearbyClient client;
        private Stack stack;
        private PreferencesGroup today_group;
        private PreferencesGroup earlier_group;
        private Box page;
        private Gee.HashSet<string> seen = new Gee.HashSet<string>();
        private bool filled = false;
        public int count { get; private set; default = 0; }

        public signal void changed(int count);

        public ReceivedView(NearbyClient client) {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            this.client = client;
            stack = new Stack();
            stack.vexpand = true;
            stack.transition_type = StackTransitionType.CROSSFADE;

            var empty = new StatusPage();
            empty.icon_name = "folder-download";
            empty.title = _("No Received Files");
            empty.description = _("Files your devices send to this computer are listed here.");
            var open_folder = new Button.with_label(_("Open Received Files Folder"));
            open_folder.add_css_class("pill");
            open_folder.halign = Align.CENTER;
            open_folder.clicked.connect(() => open_receive_folder());
            empty.child = open_folder;
            stack.add_named(empty, "empty");

            page = new Box(Orientation.VERTICAL, 18);
            page.add_css_class("nearby-page");
            Singularity.Widgets.apply_titlebar_inset(page);
            today_group = new PreferencesGroup(_("Today"));
            page.append(today_group);
            earlier_group = new PreferencesGroup(_("Earlier"));
            page.append(earlier_group);
            var scroll = new ScrolledWindow();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.child = new Singularity.Widgets.Clamp(page, 680);
            stack.add_named(scroll, "list");
            append(stack);

            client.received_files_changed.connect(() => fill.begin());
            client.notify["running"].connect(() => fill.begin());
            fill.begin();
        }

        public void open_receive_folder() {
            string folder = client.receive_folder != "" ? client.receive_folder : Environment.get_user_special_dir(UserDirectory.DOWNLOAD) ?? Environment.get_home_dir();
            try {
                AppInfo.launch_default_for_uri(File.new_for_path(folder).get_uri(), null);
            } catch (Error e) {
                warning("nearby: %s", e.message);
            }
        }

        public void clear_history() {
            client.simple.begin("ClearReceivedFiles", null);
        }

        public async void fill() {
            var list = yield client.list("GetReceivedFiles");
            today_group.clear();
            earlier_group.clear();
            stack.visible_child_name = list.length == 0 ? "empty" : "list";
            int64 now = get_real_time() / 1000000;
            var today = new DateTime.from_unix_local(now);
            Widget[] fresh = {};
            int todays = 0, earlier = 0;
            foreach (var e in list) {
                var row = build_row(e, now);
                var when = new DateTime.from_unix_local(NearbyClient.int_of(e, "time"));
                string path = NearbyClient.text_of(e, "path");
                if (when.get_year() == today.get_year() && when.get_day_of_year() == today.get_day_of_year()) {
                    today_group.add_row(row);
                    todays++;
                } else {
                    earlier_group.add_row(row);
                    earlier++;
                }
                if (filled && !seen.contains(path)) fresh += row;
                seen.add(path);
            }
            today_group.visible = todays > 0;
            earlier_group.visible = earlier > 0;
            filled = true;
            if (fresh.length > 0) Singularity.Motion.cascade(fresh, Singularity.Motion.Preset.FADE);
            count = list.length;
            changed(list.length);
        }

        private ActionRow build_row(Variant e, int64 now) {
            string path = NearbyClient.text_of(e, "path");
            string name = NearbyClient.text_of(e, "name");
            string from = NearbyClient.text_of(e, "device-name");
            bool exists = NearbyClient.flag_of(e, "exists");
            string when = Format.when(NearbyClient.int_of(e, "time"), now);
            string subtitle;
            if (!exists) subtitle = _("Moved or deleted");
            else if (from != "") subtitle = _("From %s, %s, %s").printf(from, when, Format.size(NearbyClient.int_of(e, "size")));
            else subtitle = _("%s, %s").printf(when, Format.size(NearbyClient.int_of(e, "size")));
            bool uncertain;
            string ctype = ContentType.guess(name, null, out uncertain);
            var gicon = ContentType.get_icon(ctype);
            var row = new ActionRow(name, subtitle);
            var img = new Image.from_gicon(gicon);
            img.pixel_size = 32;
            row.add_prefix(img);
            if (exists) {
                var show = new Button.from_icon_name("folder-open-symbolic");
                show.add_css_class("flat");
                show.valign = Align.CENTER;
                show.tooltip_text = _("Show in Files");
                show.update_property(AccessibleProperty.LABEL, _("Show in Files"), -1);
                show.clicked.connect(() => show_in_files(path));
                row.add_suffix(show);
                var open = new Button.with_label(_("Open"));
                open.valign = Align.CENTER;
                open.clicked.connect(() => open_file(path));
                row.add_suffix(open);
                row.activatable = true;
                row.activated.connect(() => open_file(path));
            } else {
                row.add_css_class("dim-label");
                var forget = new Button.from_icon_name("user-trash-symbolic");
                forget.add_css_class("flat");
                forget.valign = Align.CENTER;
                forget.tooltip_text = _("Remove from List");
                forget.update_property(AccessibleProperty.LABEL, _("Remove from List"), -1);
                forget.clicked.connect(() => client.simple.begin("ForgetReceivedFile", new Variant("(s)", path)));
                row.add_suffix(forget);
            }
            return row;
        }

        public static void open_file(string path) {
            var file = File.new_for_path(path);
            try {
                var recent = Gtk.RecentManager.get_default();
                var data = Gtk.RecentData();
                data.display_name = file.get_basename();
                bool uncertain;
                data.mime_type = ContentType.get_mime_type(ContentType.guess(path, null, out uncertain)) ?? "application/octet-stream";
                data.app_name = "Nearby";
                data.app_exec = "singularity-nearby-app %u";
                recent.add_full(file.get_uri(), data);
                AppInfo.launch_default_for_uri(file.get_uri(), null);
            } catch (Error e) {
                warning("nearby: cannot open %s: %s", path, e.message);
            }
        }

        public static void show_in_files(string path) {
            string uri = File.new_for_path(path).get_uri();
            string[] items = { uri };
            try {
                var bus = Bus.get_sync(BusType.SESSION, null);
                bus.call.begin("org.freedesktop.FileManager1", "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1", "ShowItems",
                    new Variant("(^ass)", items, ""), null, DBusCallFlags.NONE, 5000, null, (o, r) => {
                        try {
                            bus.call.end(r);
                        } catch (Error e) {
                            var parent = File.new_for_path(path).get_parent();
                            if (parent != null) {
                                try {
                                    AppInfo.launch_default_for_uri(parent.get_uri(), null);
                                } catch (Error e2) {
                                    warning("nearby: %s", e2.message);
                                }
                            }
                        }
                    });
            } catch (Error e) {
                warning("nearby: %s", e.message);
            }
        }
    }
}
