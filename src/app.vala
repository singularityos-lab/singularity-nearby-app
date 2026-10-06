using Gtk;

namespace Singularity.Apps.Nearby {

    [DBus (name = "dev.sinty.NearbyApp1")]
    public class Presenter : Object {
        private unowned NearbyApp app;

        public Presenter(NearbyApp app) {
            this.app = app;
        }

        public void present(string device_id, string page) throws DBusError, IOError {
            app.present_device(device_id != "" ? device_id : null, page != "" ? page : null);
        }
    }

    public class NearbyApp : Singularity.Application {
        public const string UNIQUE_NAME = "dev.sinty.Nearby.App";
        public const string PRESENTER_PATH = "/dev/sinty/Nearby/App";

        public NearbyClient client;
        public TransferStore transfers;
        private NearbyWindow? window = null;
        private Singularity.DockMenu? dock_menu = null;
        private string dock_signature = "";
        private string? pending_device = null;
        private string? pending_page = null;
        private bool service_mode = false;
        private bool held = false;
        private uint idle_id = 0;

        public NearbyApp() {
            Object(application_id: "dev.sinty.Nearby", flags: ApplicationFlags.NON_UNIQUE);
            add_main_option("device", 0, OptionFlags.NONE, OptionArg.STRING, _("Show a paired device"), _("ID"));
            add_main_option("page", 0, OptionFlags.NONE, OptionArg.STRING, _("Open a page: pair, received, send-files, send-link, messages or notifications"), _("PAGE"));
            add_main_option("search-service", 0, OptionFlags.HIDDEN, OptionArg.NONE, _("Answer desktop searches without a window"), null);
        }

        protected override int handle_local_options(VariantDict options) {
            var dv = options.lookup_value("device", VariantType.STRING);
            var pv = options.lookup_value("page", VariantType.STRING);
            pending_device = dv != null ? dv.get_string() : null;
            pending_page = pv != null ? pv.get_string() : null;
            service_mode = options.contains("search-service");
            DBusConnection bus;
            try {
                bus = Bus.get_sync(BusType.SESSION, null);
            } catch (Error e) {
                warning("nearby: %s", e.message);
                return -1;
            }
            try {
                register(null);
            } catch (Error e) {
                warning("nearby: %s", e.message);
                return 1;
            }
            try {
                bus.register_object(PRESENTER_PATH, new Presenter(this));
            } catch (IOError e) {
                warning("nearby: %s", e.message);
            }
            uint32 result = 0;
            try {
                var reply = bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName",
                    new Variant("(su)", UNIQUE_NAME, 4), new VariantType("(u)"), DBusCallFlags.NONE, 5000, null);
                result = reply.get_child_value(0).get_uint32();
            } catch (Error e) {
                warning("nearby: %s", e.message);
                return -1;
            }
            if (result == 1 || result == 4) return -1;
            if (service_mode) return 0;
            try {
                bus.call_sync(UNIQUE_NAME, PRESENTER_PATH, "dev.sinty.NearbyApp1", "Present",
                    new Variant("(ss)", pending_device ?? "", pending_page ?? ""), null, DBusCallFlags.NONE, 5000, null);
                return 0;
            } catch (Error e) {
                warning("nearby: cannot reach the running window: %s", e.message);
                return -1;
            }
        }

        protected override void startup() {
            base.startup();
            client = NearbyClient.get_default();
            client.start();
            transfers = new TransferStore(client);
            var provider = new CssProvider();
            provider.load_from_string(CSS);
            StyleContext.add_provider_for_display(Gdk.Display.get_default(), provider, STYLE_PROVIDER_PRIORITY_USER + 1);

            var menu = new GLib.Menu();
            var file = new GLib.Menu();
            var f1 = new GLib.Menu();
            f1.append(_("Send Files…"), "win.send-files");
            f1.append(_("Send Link…"), "win.send-link");
            f1.append(_("Pair a Device…"), "win.pair");
            file.append_section(null, f1);
            var f2 = new GLib.Menu();
            f2.append(_("Close Window"), "win.close");
            f2.append(_("Quit"), "app.quit");
            file.append_section(null, f2);
            menu.append_submenu(_("File"), file);
            var edit = new GLib.Menu();
            edit.append(_("Settings"), "app.settings");
            menu.append_submenu(_("Edit"), edit);
            var view = new GLib.Menu();
            view.append(_("Received Files"), "win.received");
            view.append(_("Toggle Sidebar"), "win.toggle-sidebar");
            menu.append_submenu(_("View"), view);
            set_menubar(menu);

            var quit = new SimpleAction("quit", null);
            quit.activate.connect(() => {
                foreach (var w in get_windows()) w.close();
            });
            add_action(quit);
            var settings_action = new SimpleAction("settings", null);
            settings_action.activate.connect(() => NearbyClient.open_settings());
            add_action(settings_action);
            set_accels_for_action("win.close", { "<Control>w" });
            set_accels_for_action("app.quit", { "<Control>q" });
            set_accels_for_action("win.send-files", { "<Control>o" });
            set_accels_for_action("win.send-link", { "<Control>l" });
            set_accels_for_action("win.received", { "<Control>j" });
            set_accels_for_action("win.back", { "<Alt>Left" });
            set_accels_for_action("app.settings", { "<Control>comma" });

            dock_menu = new Singularity.DockMenu("dev.sinty.Nearby");
            dock_menu.activated.connect((id) => {
                if (id.has_prefix("send:")) present_device(id.substring(5), "send-files");
                else if (id.has_prefix("device:")) present_device(id.substring(7), null);
                else if (id == "received") present_device(null, "received");
            });
            client.changed.connect(() => publish_dock());
            publish_dock();

            if (service_mode) {
                hold();
                held = true;
                touch();
            }
        }

        public override void activate() {
            if (service_mode && pending_device == null && pending_page == null) return;
            present_device(pending_device, pending_page);
            pending_device = null;
            pending_page = null;
        }

        public void touch() {
            if (!held) return;
            if (idle_id != 0) Source.remove(idle_id);
            idle_id = Timeout.add_seconds(30, () => {
                idle_id = 0;
                if (held) {
                    held = false;
                    release();
                }
                return Source.REMOVE;
            });
        }

        public void present_device(string? device_id, string? page) {
            if (held) {
                held = false;
                if (idle_id != 0) Source.remove(idle_id);
                idle_id = 0;
                service_mode = false;
                window = ensure_window();
                release();
            }
            var w = ensure_window();
            w.present();
            if (device_id != null && device_id != "") {
                if (page == "send-files") {
                    w.show_device(device_id);
                    w.send_files(device_id);
                    return;
                }
                w.show_device(device_id);
            }
            if (page != null && page != "") w.open_page(page);
        }

        private NearbyWindow ensure_window() {
            if (window == null) {
                window = new NearbyWindow(this, client, transfers);
                window.close_request.connect(() => {
                    window = null;
                    return false;
                });
                window.show_welcome();
            }
            return window;
        }

        private void publish_dock() {
            if (dock_menu == null) return;
            var sig = new StringBuilder();
            var usable = new Gee.ArrayList<NearbyDevice>();
            foreach (var d in client.devices) {
                if (!d.paired) continue;
                usable.add(d);
                sig.append("%s|%s|%d;".printf(d.id, d.name, d.usable ? 1 : 0));
            }
            if (sig.str == dock_signature) return;
            dock_signature = sig.str;
            dock_menu.clear();
            foreach (var d in usable) {
                if (d.usable && d.has_plugin("share")) dock_menu.add_item("send:" + d.id, _("Send Files to %s").printf(d.name), "document-send-symbolic");
                else dock_menu.add_item("device:" + d.id, d.name, d.icon_name);
            }
            if (usable.size > 0) dock_menu.publish();
            else dock_menu.unpublish();
        }

        private const string CSS = """
.nearby-page {
    margin: 24px 28px 28px 28px;
}

.nearby-drop {
    padding: 22px 18px;
    border-radius: 18px;
    border: 2px dashed alpha(@window_fg_color, 0.18);
    background-color: alpha(@window_fg_color, 0.03);
    transition: background-color var(--motion-duration-small, 140ms) ease, border-color var(--motion-duration-small, 140ms) ease;
}

.nearby-drop:hover {
    background-color: alpha(@accent_bg_color, 0.06);
}

.nearby-drop.nearby-drop-hover,
.nearby-drop-hover .nearby-drop {
    border-color: @accent_bg_color;
    background-color: alpha(@accent_bg_color, 0.14);
}

.singularity-sidebar-row.nearby-drop-hover {
    background-color: alpha(@accent_bg_color, 0.22);
}

.nearby-code-cell {
    font-size: 30px;
    font-weight: 800;
    min-width: 36px;
    padding: 10px 4px;
    border-radius: 12px;
    background-color: alpha(@window_fg_color, 0.07);
}

.nearby-check {
    color: white;
    background-color: @success_color;
    border-radius: 99px;
    padding: 6px;
    box-shadow: 0 0 0 3px @window_bg_color;
}

.nearby-bubble {
    background-color: alpha(@window_fg_color, 0.07);
    border-radius: 18px;
}

.nearby-bubble.mine {
    background-color: @accent_bg_color;
    color: @accent_fg_color;
}

.nearby-composer {
    padding: 10px 16px 14px 16px;
}

.nearby-conversations {
    background-color: alpha(@window_fg_color, 0.02);
}

.nearby-avatar {
    min-width: 36px;
    min-height: 36px;
    border-radius: 99px;
    font-weight: 800;
    color: white;
    background-color: alpha(@accent_bg_color, 0.85);
}

.nearby-notification {
    padding: 14px 16px;
    border-radius: 16px;
    background-color: alpha(@window_fg_color, 0.05);
}

.nearby-badge {
    font-size: 11px;
    font-weight: 800;
    min-width: 18px;
    padding: 0 5px;
    border-radius: 99px;
    color: @accent_fg_color;
    background-color: @accent_bg_color;
}

.nearby-away {
    opacity: 0.6;
}

.nearby-play {
    min-width: 40px;
    min-height: 40px;
    padding: 0;
    border-radius: 99px;
    background-color: alpha(@window_fg_color, 0.08);
}
""";
    }

    public static int main(string[] args) {
        Intl.setlocale(LocaleCategory.ALL, "");
        string locale_dir = "/usr/share/locale";
        try {
            string exe = FileUtils.read_link("/proc/self/exe");
            locale_dir = Path.build_filename(Path.get_dirname(Path.get_dirname(exe)), "share", "locale");
        } catch (Error e) {
        }
        Intl.bindtextdomain("singularity-nearby-app", locale_dir);
        Intl.bind_textdomain_codeset("singularity-nearby-app", "UTF-8");
        Intl.textdomain("singularity-nearby-app");
        Environment.set_application_name(_("Nearby"));
        var app = new NearbyApp();
        new NearbySearch(app).export(app, "/dev/sinty/Nearby/SearchProvider");
        return app.run(args);
    }
}
