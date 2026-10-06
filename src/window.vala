using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Nearby {

    public class NearbyWindow : Singularity.Widgets.Window {
        private NearbyApp app;
        private NearbyClient client;
        private TransferStore transfers;
        private AppSidebar sidebar;
        private Stack stack;
        private WelcomePage welcome;
        private StatusPage unavailable;
        private DeviceView device_view;
        private MessagesView messages_view;
        private NotificationsView notifications_view;
        private ReceivedView received_view;
        private PairingView pairing_view;
        private Button back_bubble;
        private Button new_message_bubble;
        private Button clear_bubble;
        private Button folder_bubble;
        private string selected = "";
        private string pending_show = "";
        private string pending_page = "";
        private string sidebar_signature = "";
        private Gee.HashMap<string, SidebarRow> rows = new Gee.HashMap<string, SidebarRow>();
        private Gee.ArrayList<string> history = new Gee.ArrayList<string>();

        public NearbyWindow(NearbyApp app, NearbyClient client, TransferStore transfers) {
            Object(application: app);
            this.app = app;
            this.client = client;
            this.transfers = transfers;
            set_default_size(1040, 740);
            set_title(_("Nearby"));

            sidebar = new AppSidebar(240);
            set_sidebar(sidebar);
            set_sidebar_visible(true);

            stack = new Stack();
            stack.transition_type = StackTransitionType.CROSSFADE;
            stack.transition_duration = Singularity.Motion.Duration.MEDIUM;

            welcome = new WelcomePage();
            welcome.app_icon_name = "dev.sinty.Nearby";
            welcome.title = _("Nearby");
            welcome.subtitle = _("Send files and links to your phone, read its messages and notifications here, and share the clipboard.");
            welcome.add_action("singularity-share-send-files", _("Send Files"), _("To a paired phone or computer"), () => send_files(null));
            welcome.add_action("singularity-share-link", _("Send Link"), _("Open a web page on your phone"), () => SendDialogs.send_link(app, client, null));
            welcome.add_action("phone", _("Pair a Device"), _("KDE Connect on Android and iPhone, GSConnect on computers"), () => show_pairing(null));
            stack.add_named(welcome, "welcome");

            unavailable = new StatusPage();
            unavailable.icon_name = "dev.sinty.Nearby";
            unavailable.title = _("Nearby Is Not Available");
            unavailable.description = _("The Nearby service is not installed or is turned off on this system.");
            stack.add_named(unavailable, "unavailable");

            device_view = new DeviceView(client, transfers);
            device_view.send_files_requested.connect((id) => send_files(id));
            device_view.send_link_requested.connect((id) => SendDialogs.send_link(app, client, id));
            device_view.files_dropped.connect((id, files) => send_to(id, files));
            device_view.open_messages.connect((id) => show_messages(id));
            device_view.open_notifications.connect((id) => show_notifications(id));
            device_view.unpair_requested.connect((id) => confirm_unpair(id));
            device_view.open_received.connect((path) => ReceivedView.open_file(path));
            stack.add_named(device_view, "device");

            messages_view = new MessagesView(client);
            stack.add_named(messages_view, "messages");

            notifications_view = new NotificationsView(client);
            stack.add_named(notifications_view, "notifications");

            received_view = new ReceivedView(client);
            stack.add_named(received_view, "received");

            pairing_view = new PairingView(client);
            pairing_view.paired.connect((id) => show_device(id));
            pairing_view.device_chosen.connect((id) => show_pairing(id));
            stack.add_named(pairing_view, "pairing");

            set_content(stack);

            back_bubble = add_bubble_icon("go-previous-symbolic", _("Back"), () => go_back());
            new_message_bubble = add_bubble_icon("mail-message-new-symbolic", _("New Message"), () => messages_view.new_message());
            folder_bubble = add_bubble_icon("folder-open-symbolic", _("Open Received Files Folder"), () => received_view.open_receive_folder());
            clear_bubble = add_bubble_text(_("Clear History"), () => received_view.clear_history());
            received_view.changed.connect((count) => update_bubbles());
            stack.notify["visible-child-name"].connect(() => update_bubbles());

            install_actions();
            client.changed.connect(() => sync());
            client.pair_requested.connect((id, name, code) => {
                if (is_active || stack.visible_child_name == "pairing") show_pairing(id);
            });
            sync();
            update_bubbles();
        }

        private void install_actions() {
            string[] names = { "close", "send-files", "send-link", "pair", "received", "toggle-sidebar", "back" };
            foreach (string n in names) {
                var a = new SimpleAction(n, null);
                string name = n;
                a.activate.connect(() => run_action(name));
                add_action(a);
            }
        }

        private void run_action(string name) {
            switch (name) {
                case "close": close(); break;
                case "send-files": send_files(stack.visible_child_name == "device" ? selected : null); break;
                case "send-link": SendDialogs.send_link(app, client, stack.visible_child_name == "device" ? selected : null); break;
                case "pair": show_pairing(null); break;
                case "received": show_received(); break;
                case "toggle-sidebar": set_sidebar_visible(!get_sidebar_visible()); break;
                case "back": go_back(); break;
            }
        }

        private void update_bubbles() {
            string page = stack.visible_child_name ?? "";
            back_bubble.visible = page == "messages" || page == "notifications" || (page == "pairing" && history.size > 0);
            new_message_bubble.visible = page == "messages";
            folder_bubble.visible = page == "received";
            clear_bubble.visible = page == "received" && received_view.count > 0;
        }

        private void go_back() {
            string page = stack.visible_child_name ?? "";
            if ((page == "messages" || page == "notifications") && selected != "") {
                show_device(selected);
                return;
            }
            if (history.size > 0) {
                string prev = history.remove_at(history.size - 1);
                if (prev.has_prefix("device:")) show_device(prev.substring(7), false);
                else if (prev == "received") show_received(false);
                else show_welcome();
                return;
            }
            show_welcome();
        }

        private void remember() {
            string page = stack.visible_child_name ?? "";
            string key = page == "device" ? "device:" + selected : page;
            if (key == "welcome" || key == "pairing" || key == "") return;
            if (history.size > 0 && history[history.size - 1] == key) return;
            history.add(key);
            while (history.size > 12) history.remove_at(0);
        }

        private void set_page(string name) {
            stack.visible_child_name = name;
            highlight();
        }

        public void show_welcome() {
            selected = "";
            set_page(client.available ? "welcome" : "unavailable");
        }

        public void show_device(string id, bool push = true) {
            var d = client.find(id);
            if (d == null) {
                if (client.devices.size == 0) pending_show = id;
                show_welcome();
                return;
            }
            pending_show = "";
            if (!d.paired) {
                show_pairing(id);
                return;
            }
            if (push && stack.visible_child_name != "device") remember();
            if (selected != id) selected = id;
            device_view.show_device(id);
            set_page("device");
        }

        public void show_messages(string id) {
            if (selected != id) selected = id;
            messages_view.show_device(id);
            set_page("messages");
        }

        public void show_notifications(string id) {
            if (selected != id) selected = id;
            notifications_view.show_device(id);
            set_page("notifications");
        }

        public void show_received(bool push = true) {
            if (push) remember();
            selected = "";
            received_view.fill.begin();
            set_page("received");
        }

        public void show_pairing(string? id) {
            remember();
            string target = id ?? "";
            if (selected != target) selected = target;
            if (id == null) pairing_view.show_list();
            else pairing_view.show_device(id);
            set_page("pairing");
        }

        public void open_page(string page) {
            if (pending_show != "" && (page == "messages" || page == "notifications")) {
                pending_page = page;
                return;
            }
            switch (page) {
                case "pair": show_pairing(null); break;
                case "received": show_received(); break;
                case "send-files": send_files(null); break;
                case "send-link": SendDialogs.send_link(app, client, null); break;
                case "messages": if (selected != "") show_messages(selected); break;
                case "notifications": if (selected != "") show_notifications(selected); break;
            }
        }

        public void send_files(string? device_id) {
            if (device_id == null || device_id == "") {
                SendDialogs.pick_device(app, client, _("Send Files"), (id) => choose_and_send(id));
                return;
            }
            choose_and_send(device_id);
        }

        private void choose_and_send(string device_id) {
            var d = client.find(device_id);
            var dialog = new FileDialog();
            dialog.title = _("Send Files");
            if (d != null) dialog.title = _("Send Files to %s").printf(d.name);
            dialog.accept_label = _("Send");
            dialog.open_multiple.begin(this, null, (o, r) => {
                try {
                    var model = dialog.open_multiple.end(r);
                    File[] files = {};
                    for (uint i = 0; i < model.get_n_items(); i++) files += (File) model.get_item(i);
                    if (files.length > 0) send_to(device_id, files);
                } catch (Error e) {
                }
            });
        }

        public void send_to(string device_id, File[] files) {
            client.share_files.begin(device_id, files, (o, r) => {
                try {
                    client.share_files.end(r);
                } catch (Error e) {
                    var t = new Toast(e.message);
                    add_toast(t);
                }
            });
            if (stack.visible_child_name != "device" || selected != device_id) show_device(device_id);
        }

        private void confirm_unpair(string id) {
            var d = client.find(id);
            if (d == null) return;
            var dlg = new ConfirmDialog(app, _("Unpair %s?").printf(d.name), Format.device_icon(d.device_type),
                _("It will no longer share files, the clipboard or notifications with this computer until you pair again."),
                _("Unpair"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.response.connect((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                client.simple.begin("Unpair", new Variant("(s)", id));
                history.clear();
                show_welcome();
            });
            dlg.present();
        }

        private void sync() {
            bool ok = client.available;
            var mine = new Gee.ArrayList<NearbyDevice>();
            var others = new Gee.ArrayList<NearbyDevice>();
            foreach (var d in client.devices) {
                if (d.paired) mine.add(d);
                else if (d.reachable) others.add(d);
            }
            var sig = new StringBuilder();
            foreach (var d in mine) sig.append("%s|%s|%d|%d|%d;".printf(d.id, d.name, d.reachable ? 1 : 0, d.battery, d.notification_count));
            sig.append("#");
            foreach (var d in others) sig.append("%s|%s|%s;".printf(d.id, d.name, d.pair_state));
            sig.append(ok ? "1" : "0");
            if (sig.str != sidebar_signature) {
                sidebar_signature = sig.str;
                rebuild_sidebar(mine, others);
            }
            string page = stack.visible_child_name ?? "";
            if (!ok) {
                set_page("unavailable");
                return;
            }
            if (page == "unavailable") show_welcome();
            if (pending_show != "" && client.find(pending_show) != null) {
                string id = pending_show;
                string then = pending_page;
                pending_show = "";
                pending_page = "";
                show_device(id);
                if (then != "") open_page(then);
                return;
            }
            if ((page == "device" || page == "messages" || page == "notifications") && selected != "") {
                var d = client.find(selected);
                if (d == null || !d.paired) show_welcome();
            }
            highlight();
        }

        private void rebuild_sidebar(Gee.List<NearbyDevice> mine, Gee.List<NearbyDevice> others) {
            var child = sidebar.box.get_first_child();
            while (child != null) {
                var next = child.get_next_sibling();
                sidebar.box.remove(child);
                child = next;
            }
            rows.clear();
            if (mine.size > 0) sidebar.box.append(new SidebarSectionLabel(_("My Devices")));
            foreach (var d in mine) {
                var row = new SidebarRow(d.icon_name, d.name);
                var box = row.get_child() as Box;
                if (box != null) {
                    string hint_text = "";
                    if (!d.reachable) hint_text = _("Away");
                    else if (d.battery >= 0) hint_text = Format.battery(d.battery, false);
                    if (hint_text != "") {
                        var hint = new Label(hint_text);
                        hint.add_css_class("dim-label");
                        hint.add_css_class("caption");
                        box.append(hint);
                    }
                    if (d.notification_count > 0) {
                        var badge = new Label(d.notification_count.to_string());
                        badge.add_css_class("nearby-badge");
                        box.append(badge);
                    }
                }
                if (!d.reachable) row.add_css_class("nearby-away");
                string id = d.id;
                row.clicked.connect(() => show_device(id));
                DropZone.attach(row, (files) => {
                    var dev = client.find(id);
                    if (dev != null && dev.usable) send_to(id, files);
                });
                rows["device:" + id] = row;
                sidebar.box.append(row);
            }
            if (others.size > 0) sidebar.box.append(new SidebarSectionLabel(_("Nearby")));
            foreach (var d in others) {
                var row = new SidebarRow(d.icon_name, d.name);
                string id = d.id;
                row.clicked.connect(() => show_pairing(id));
                rows["pair:" + id] = row;
                sidebar.box.append(row);
            }
            sidebar.box.append(new SidebarSectionLabel(_("This Computer")));
            var received = new SidebarRow("folder-download-symbolic", _("Received Files"));
            received.clicked.connect(() => show_received());
            rows["received"] = received;
            sidebar.box.append(received);
            var pair = new SidebarRow("list-add-symbolic", _("Pair a Device"));
            pair.clicked.connect(() => show_pairing(null));
            rows["pairing"] = pair;
            sidebar.box.append(pair);
            var settings = new SidebarRow("emblem-system-symbolic", _("Nearby Settings"));
            settings.clicked.connect(() => NearbyClient.open_settings());
            sidebar.box.append(settings);
            highlight();
        }

        private void highlight() {
            string page = stack.visible_child_name ?? "";
            string key = "";
            if (page == "device" || page == "messages" || page == "notifications") key = "device:" + selected;
            else if (page == "received") key = "received";
            else if (page == "pairing") key = selected != "" ? "pair:" + selected : "pairing";
            foreach (var e in rows.entries) e.value.set_active(e.key == key);
        }
    }
}
