using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Nearby {

    public class TransferRow : PreferencesRow {
        public TransferItem item;
        private Label title;
        private Label status;
        private ProgressBar bar;
        private Box buttons;

        public signal void accept(string batch);
        public signal void decline(string batch);
        public signal void open_file(string path);

        public TransferRow(TransferItem item) {
            this.item = item;
            activatable = false;
            var box = new Box(Orientation.HORIZONTAL, 12);
            box.margin_top = 10;
            box.margin_bottom = 10;
            box.margin_start = 12;
            box.margin_end = 12;
            var icon = new Image.from_icon_name(item.incoming ? "folder-download-symbolic" : "document-send-symbolic");
            icon.valign = Align.CENTER;
            box.append(icon);
            var col = new Box(Orientation.VERTICAL, 4);
            col.hexpand = true;
            title = new Label(item.name);
            title.xalign = 0;
            title.ellipsize = Pango.EllipsizeMode.MIDDLE;
            col.append(title);
            status = new Label("");
            status.xalign = 0;
            status.add_css_class("dim-label");
            status.add_css_class("caption");
            status.ellipsize = Pango.EllipsizeMode.END;
            col.append(status);
            bar = new ProgressBar();
            col.append(bar);
            box.append(col);
            buttons = new Box(Orientation.HORIZONTAL, 6);
            buttons.valign = Align.CENTER;
            box.append(buttons);
            child = box;
            update();
        }

        public void update() {
            title.label = item.name;
            status.label = item.status();
            bar.visible = item.state == "running";
            bar.fraction = Format.fraction(item.done, item.total);
            if (item.state == "failed") status.add_css_class("error");
            else status.remove_css_class("error");
            var child = buttons.get_first_child();
            while (child != null) {
                var next = child.get_next_sibling();
                buttons.remove(child);
                child = next;
            }
            if (item.state == "waiting" && item.batch != "") {
                var no = new Button.with_label(_("Decline"));
                no.clicked.connect(() => decline(item.batch));
                buttons.append(no);
                var yes = new Button.with_label(_("Accept"));
                yes.add_css_class("suggested-action");
                yes.clicked.connect(() => accept(item.batch));
                buttons.append(yes);
            } else if (item.state == "done" && item.incoming && item.detail.has_prefix("/")) {
                var open = new Button.with_label(_("Open"));
                string path = item.detail;
                open.clicked.connect(() => open_file(path));
                buttons.append(open);
            }
        }
    }

    public class DeviceView : Box {
        private NearbyClient client;
        private TransferStore transfers;
        private string device_id = "";
        private Image icon;
        private Singularity.Animation.MotionBin icon_bin;
        private Label name_label;
        private Label status_label;
        private Box battery_box;
        private Image battery_icon;
        private Label battery_label;
        private LevelBar battery_bar;
        private Button send_btn;
        private Button link_btn;
        private Button ring_btn;
        private DropZone drop_zone;
        private PreferencesGroup transfers_group;
        private PreferencesGroup media_group;
        private PreferencesGroup phone_group;
        private ActionRow messages_row;
        private ActionRow notifications_row;
        private SwitchRow clipboard_row;
        private SwitchRow always_row;
        private PreferencesGroup sharing_group;
        private PreferencesGroup features_group;
        private Gee.HashMap<string, SwitchRow> feature_rows = new Gee.HashMap<string, SwitchRow>();
        private Gee.HashMap<string, TransferRow> transfer_rows = new Gee.HashMap<string, TransferRow>();
        private Button unpair_btn;
        private bool syncing = false;
        private string shown_device = "";
        private string transfers_signature = "";
        private string media_signature = "";
        private ScrolledWindow scroll;

        public signal void send_files_requested(string device_id);
        public signal void send_link_requested(string device_id);
        public signal void files_dropped(string device_id, File[] files);
        public signal void open_messages(string device_id);
        public signal void open_notifications(string device_id);
        public signal void unpair_requested(string device_id);
        public signal void open_received(string path);

        public DeviceView(NearbyClient client, TransferStore transfers) {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            this.client = client;
            this.transfers = transfers;

            var page = new Box(Orientation.VERTICAL, 18);
            page.add_css_class("nearby-page");
            Singularity.Widgets.apply_titlebar_inset(page);

            var header = new Box(Orientation.HORIZONTAL, 18);
            icon = new Image.from_icon_name("phone");
            icon.pixel_size = 88;
            icon_bin = new Singularity.Animation.MotionBin(icon);
            header.append(icon_bin);
            var titles = new Box(Orientation.VERTICAL, 4);
            titles.valign = Align.CENTER;
            titles.hexpand = true;
            name_label = new Label("");
            name_label.xalign = 0;
            name_label.add_css_class("title-1");
            name_label.ellipsize = Pango.EllipsizeMode.END;
            titles.append(name_label);
            status_label = new Label("");
            status_label.xalign = 0;
            status_label.add_css_class("dim-label");
            titles.append(status_label);
            battery_box = new Box(Orientation.HORIZONTAL, 8);
            battery_box.margin_top = 4;
            battery_icon = new Image.from_icon_name("battery-full-symbolic");
            battery_box.append(battery_icon);
            battery_bar = new LevelBar.for_interval(0, 100);
            battery_bar.width_request = 120;
            battery_bar.valign = Align.CENTER;
            battery_bar.add_css_class("nearby-battery");
            battery_box.append(battery_bar);
            battery_label = new Label("");
            battery_label.add_css_class("numeric");
            battery_box.append(battery_label);
            titles.append(battery_box);
            header.append(titles);
            page.append(header);

            var actions = new Box(Orientation.HORIZONTAL, 8);
            actions.add_css_class("nearby-actions");
            send_btn = pill("document-send-symbolic", _("Send Files…"), () => send_files_requested(device_id));
            send_btn.add_css_class("suggested-action");
            actions.append(send_btn);
            link_btn = pill("insert-link-symbolic", _("Send Link…"), () => send_link_requested(device_id));
            actions.append(link_btn);
            ring_btn = pill("audio-volume-high-symbolic", _("Ring"), () => {
                client.simple.begin("Ring", new Variant("(s)", device_id));
                Singularity.Motion.spring_to(icon_bin, "scale", 1.08, Singularity.Motion.Spring.BOUNCY).done.connect(() => {
                    Singularity.Motion.spring_to(icon_bin, "scale", 1.0, Singularity.Motion.Spring.SNAPPY);
                });
            });
            actions.append(ring_btn);
            page.append(actions);

            drop_zone = new DropZone();
            drop_zone.files_dropped.connect((files) => files_dropped(device_id, files));
            drop_zone.browse.connect(() => send_files_requested(device_id));
            page.append(drop_zone);

            transfers_group = new PreferencesGroup(_("Transfers"));
            page.append(transfers_group);

            media_group = new PreferencesGroup(_("Now Playing"));
            page.append(media_group);

            phone_group = new PreferencesGroup(_("Phone"));
            messages_row = new ActionRow(_("Messages"), _("Read and send text messages"), "mail-message-new-symbolic");
            messages_row.activatable = true;
            messages_row.add_suffix(chevron());
            messages_row.activated.connect(() => open_messages(device_id));
            phone_group.add_row(messages_row);
            notifications_row = new ActionRow(_("Notifications"), "", "preferences-system-notifications-symbolic");
            notifications_row.activatable = true;
            notifications_row.add_suffix(chevron());
            notifications_row.activated.connect(() => open_notifications(device_id));
            phone_group.add_row(notifications_row);
            page.append(phone_group);

            sharing_group = new PreferencesGroup(_("Sharing"));
            clipboard_row = new SwitchRow(_("Shared Clipboard"), _("Copy on one device, paste on the other"), false);
            clipboard_row.switch_btn.notify["active"].connect(() => {
                if (syncing) return;
                client.simple.begin("SetPluginEnabled", new Variant("(ssb)", device_id, "clipboard", clipboard_row.switch_btn.active));
            });
            sharing_group.add_row(clipboard_row);
            always_row = new SwitchRow(_("Accept Files Without Asking"), _("Files from this device go straight to the Received Files folder"), false);
            always_row.switch_btn.notify["active"].connect(() => {
                if (syncing) return;
                client.simple.begin("SetAlwaysAllowFiles", new Variant("(sb)", device_id, always_row.switch_btn.active));
            });
            sharing_group.add_row(always_row);
            page.append(sharing_group);

            features_group = new PreferencesGroup(_("Features"), _("Turned off features ignore everything the device sends for them."));
            foreach (string plugin in NearbyClient.PLUGINS) {
                if (plugin == "clipboard") continue;
                var row = new SwitchRow(NearbyClient.feature_title(plugin), NearbyClient.feature_description(plugin), false);
                string p = plugin;
                row.switch_btn.notify["active"].connect(() => {
                    if (syncing) return;
                    client.simple.begin("SetPluginEnabled", new Variant("(ssb)", device_id, p, row.switch_btn.active));
                });
                feature_rows[plugin] = row;
                features_group.add_row(row);
            }
            page.append(features_group);

            unpair_btn = new Button.with_label(_("Unpair"));
            unpair_btn.add_css_class("pill");
            unpair_btn.add_css_class("destructive-action");
            unpair_btn.halign = Align.CENTER;
            unpair_btn.margin_top = 6;
            unpair_btn.clicked.connect(() => unpair_requested(device_id));
            page.append(unpair_btn);

            scroll = new ScrolledWindow();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.child = new Singularity.Widgets.Clamp(page, 680);
            append(scroll);

            DropZone.attach(this, (files) => {
                var d = device;
                if (d != null && d.usable && d.has_plugin("share")) files_dropped(device_id, files);
            });

            client.changed.connect(() => sync());
            client.media_changed.connect((id) => {
                if (id == device_id) sync_media.begin();
            });
            client.notifications_changed.connect((id) => {
                if (id == device_id) sync();
            });
            client.conversations_changed.connect((id) => {
                if (id == device_id) sync_messages.begin();
            });
            transfers.changed.connect(() => sync_transfers());
            transfers.progress.connect((t) => {
                var row = transfer_rows[t.id];
                if (row != null) row.update();
            });
        }

        private NearbyDevice? device {
            owned get { return client.find(device_id); }
        }

        public string current_device {
            get { return device_id; }
        }

        private static Image chevron() {
            var img = new Image.from_icon_name("go-next-symbolic");
            img.pixel_size = 12;
            img.add_css_class("dim-label");
            img.valign = Align.CENTER;
            return img;
        }

        private static Button pill(string icon_name, string label, owned Singularity.Widgets.Window.BubbleAction action) {
            var btn = new Button();
            var box = new Box(Orientation.HORIZONTAL, 6);
            box.append(new Image.from_icon_name(icon_name));
            box.append(new Label(label));
            btn.child = box;
            btn.add_css_class("pill");
            btn.clicked.connect(() => action());
            return btn;
        }

        public void show_device(string id) {
            device_id = id;
            sync();
            if (shown_device != id) {
                shown_device = id;
                scroll.vadjustment.value = 0;
                Singularity.Motion.reveal(icon_bin, Singularity.Motion.Preset.SCALE_FADE);
                client.simple.begin("RequestConversations", new Variant("(s)", id));
            }
            sync_media.begin();
            sync_messages.begin();
        }

        private void sync() {
            var d = device;
            if (d == null) return;
            icon.icon_name = Format.device_icon(d.device_type);
            name_label.label = d.name;
            if (!d.reachable) status_label.label = _("Not connected. Open KDE Connect on %s.").printf(d.name);
            else if (d.address != "") status_label.label = _("Connected over Wi-Fi");
            else status_label.label = _("Connected");
            battery_box.visible = d.battery >= 0 && d.has_plugin("battery");
            if (battery_box.visible) {
                battery_icon.icon_name = d.battery_icon();
                battery_bar.value = d.battery;
                battery_label.label = Format.battery(d.battery, d.charging);
            }
            bool share = d.usable && d.has_plugin("share");
            send_btn.sensitive = share;
            link_btn.sensitive = share;
            ring_btn.visible = d.has_plugin("findmyphone") && d.supports_find;
            ring_btn.sensitive = d.usable;
            drop_zone.visible = share;
            drop_zone.set_device_name(d.name);

            phone_group.visible = (d.has_plugin("sms") && d.supports_sms) || d.has_plugin("notifications");
            messages_row.visible = d.has_plugin("sms") && d.supports_sms;
            notifications_row.visible = d.has_plugin("notifications");
            if (d.notification_count > 0) {
                notifications_row.subtitle = ngettext("%d notification from the phone", "%d notifications from the phone", d.notification_count).printf(d.notification_count);
            } else {
                notifications_row.subtitle = _("No notifications from the phone");
            }

            syncing = true;
            clipboard_row.switch_btn.active = d.has_plugin("clipboard");
            always_row.switch_btn.active = d.always_allow_files;
            always_row.visible = d.has_plugin("share");
            foreach (var entry in feature_rows.entries) {
                entry.value.switch_btn.active = d.has_plugin(entry.key);
                entry.value.visible = entry.key != "runcommand" || client.run_commands_allowed;
            }
            syncing = false;
            sync_transfers();
        }

        private void sync_transfers() {
            var list = transfers.for_device(device_id);
            var sig = new StringBuilder(device_id);
            foreach (var t in list) sig.append("|%s:%s:%s".printf(t.id, t.state, t.batch));
            if (sig.str == transfers_signature) {
                foreach (var row in transfer_rows.values) row.update();
                return;
            }
            transfers_signature = sig.str;
            transfers_group.clear();
            transfer_rows.clear();
            transfers_group.visible = list.size > 0;
            int shown = 0;
            foreach (var t in list) {
                if (++shown > 6) break;
                var row = new TransferRow(t);
                row.accept.connect((batch) => {
                    transfers.mark_batch(batch, "running");
                    client.simple.begin("AcceptTransfer", new Variant("(sb)", batch, false));
                });
                row.decline.connect((batch) => {
                    transfers.mark_batch(batch, "failed");
                    client.simple.begin("RejectTransfer", new Variant("(s)", batch));
                });
                row.open_file.connect((path) => open_received(path));
                transfer_rows[t.id] = row;
                transfers_group.add_row(row);
            }
        }

        private async void sync_messages() {
            var d = device;
            if (d == null || !d.has_plugin("sms")) return;
            var list = yield client.list("GetConversations", new Variant("(s)", device_id));
            if (list.length == 0) {
                messages_row.subtitle = _("Read and send text messages");
                return;
            }
            string who = NearbyClient.text_of(list[0], "address");
            string body = NearbyClient.text_of(list[0], "body");
            messages_row.subtitle = "%s: %s".printf(who, body);
        }

        private async void sync_media() {
            var d = device;
            if (d == null || !d.has_plugin("mpris")) {
                media_group.visible = false;
                return;
            }
            var players = yield client.list("GetPlayers", new Variant("(s)", device_id));
            var sig = new StringBuilder(device_id);
            foreach (var p in players) {
                sig.append("|%s:%s:%s:%s".printf(NearbyClient.text_of(p, "name"), NearbyClient.text_of(p, "title"),
                    NearbyClient.text_of(p, "artist"), NearbyClient.flag_of(p, "playing") ? "1" : "0"));
            }
            if (sig.str == media_signature) return;
            media_signature = sig.str;
            media_group.clear();
            int shown = 0;
            foreach (var p in players) {
                string title = NearbyClient.text_of(p, "title");
                string artist = NearbyClient.text_of(p, "artist");
                if (title == "" && artist == "") continue;
                shown++;
                string player = NearbyClient.text_of(p, "name");
                media_group.add_row(media_row(player, title, artist, NearbyClient.flag_of(p, "playing")));
            }
            media_group.visible = shown > 0;
        }

        private PreferencesRow media_row(string player, string title, string artist, bool playing) {
            var row = new PreferencesRow();
            row.activatable = false;
            var box = new Box(Orientation.HORIZONTAL, 12);
            box.margin_top = 10;
            box.margin_bottom = 10;
            box.margin_start = 12;
            box.margin_end = 12;
            var art = new Image.from_icon_name("audio-x-generic");
            art.pixel_size = 40;
            box.append(art);
            var col = new Box(Orientation.VERTICAL, 2);
            col.hexpand = true;
            col.valign = Align.CENTER;
            var t = new Label(title != "" ? title : player);
            t.xalign = 0;
            t.add_css_class("heading");
            t.ellipsize = Pango.EllipsizeMode.END;
            col.append(t);
            string byline = player;
            if (artist != "") byline = _("%s, on %s").printf(artist, player);
            var a = new Label(byline);
            a.xalign = 0;
            a.add_css_class("dim-label");
            a.ellipsize = Pango.EllipsizeMode.END;
            col.append(a);
            box.append(col);
            var controls = new Box(Orientation.HORIZONTAL, 2);
            controls.valign = Align.CENTER;
            controls.append(media_button("media-skip-backward-symbolic", _("Previous"), player, "Previous"));
            var play = media_button(playing ? "media-playback-pause-symbolic" : "media-playback-start-symbolic",
                playing ? _("Pause") : _("Play"), player, "PlayPause");
            play.add_css_class("nearby-play");
            controls.append(play);
            controls.append(media_button("media-skip-forward-symbolic", _("Next"), player, "Next"));
            box.append(controls);
            row.child = box;
            return row;
        }

        private Button media_button(string icon_name, string label, string player, string action) {
            var btn = new Button.from_icon_name(icon_name);
            btn.add_css_class("circular");
            btn.add_css_class("flat");
            btn.tooltip_text = label;
            btn.update_property(AccessibleProperty.LABEL, label, -1);
            btn.clicked.connect(() => client.simple.begin("MediaAction", new Variant("(sss)", device_id, player, action)));
            return btn;
        }
    }
}
