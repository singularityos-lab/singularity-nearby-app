using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Nearby {

    public class NotificationsView : Box {
        private NearbyClient client;
        private string device_id = "";
        private Stack stack;
        private StatusPage empty;
        private Box cards;
        private Gee.HashSet<string> seen = new Gee.HashSet<string>();

        public NotificationsView(NearbyClient client) {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            this.client = client;
            stack = new Stack();
            stack.vexpand = true;
            stack.transition_type = StackTransitionType.CROSSFADE;
            empty = new StatusPage();
            empty.icon_name = "preferences-system-notifications";
            empty.title = _("No Notifications");
            empty.description = _("Notifications from the phone show up here and in the notification center.");
            stack.add_named(empty, "empty");
            cards = new Box(Orientation.VERTICAL, 10);
            cards.add_css_class("nearby-page");
            Singularity.Widgets.apply_titlebar_inset(cards);
            var scroll = new ScrolledWindow();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.child = new Singularity.Widgets.Clamp(cards, 620);
            stack.add_named(scroll, "list");
            append(stack);
            client.notifications_changed.connect((id) => {
                if (id == device_id) fill.begin();
            });
        }

        public void show_device(string id) {
            if (id != device_id) seen.clear();
            device_id = id;
            fill.begin();
        }

        private async void fill() {
            var list = yield client.list("GetNotifications", new Variant("(s)", device_id));
            var child = cards.get_first_child();
            while (child != null) {
                var next = child.get_next_sibling();
                cards.remove(child);
                child = next;
            }
            stack.visible_child_name = list.length == 0 ? "empty" : "list";
            Widget[] fresh = {};
            var now_seen = new Gee.HashSet<string>();
            foreach (var n in list) {
                string key = NearbyClient.text_of(n, "key");
                var card = build_card(n);
                var bin = new Singularity.Animation.MotionBin(card);
                cards.append(bin);
                if (!seen.contains(key)) fresh += bin;
                now_seen.add(key);
            }
            seen = now_seen;
            if (fresh.length > 0) Singularity.Motion.cascade(fresh, Singularity.Motion.Preset.FADE_SLIDE);
        }

        private Widget build_card(Variant n) {
            string key = NearbyClient.text_of(n, "key");
            var card = new Box(Orientation.VERTICAL, 8);
            card.add_css_class("card");
            card.add_css_class("nearby-notification");
            var top = new Box(Orientation.HORIZONTAL, 10);
            string icon_path = NearbyClient.text_of(n, "icon");
            Image icon;
            if (icon_path != "" && FileUtils.test(icon_path, FileTest.EXISTS)) {
                icon = new Image.from_file(icon_path);
            } else {
                icon = new Image.from_icon_name("preferences-system-notifications");
            }
            icon.pixel_size = 32;
            icon.valign = Align.START;
            top.append(icon);
            var col = new Box(Orientation.VERTICAL, 2);
            col.hexpand = true;
            var app = new Label(NearbyClient.text_of(n, "app"));
            app.xalign = 0;
            app.add_css_class("caption");
            app.add_css_class("dim-label");
            col.append(app);
            string title = NearbyClient.text_of(n, "title");
            if (title != "") {
                var t = new Label(title);
                t.xalign = 0;
                t.wrap = true;
                t.add_css_class("heading");
                col.append(t);
            }
            string text = NearbyClient.text_of(n, "text");
            if (text != "") {
                var b = new Label(text);
                b.xalign = 0;
                b.wrap = true;
                b.wrap_mode = Pango.WrapMode.WORD_CHAR;
                col.append(b);
            }
            top.append(col);
            var when = new Label(Format.when(NearbyClient.int_of(n, "time") / 1000, get_real_time() / 1000000));
            when.add_css_class("caption");
            when.add_css_class("dim-label");
            when.valign = Align.START;
            top.append(when);
            card.append(top);

            var buttons = new Box(Orientation.HORIZONTAL, 6);
            buttons.halign = Align.END;
            var actions = n.lookup_value("actions", VariantType.STRING_ARRAY);
            if (actions != null) {
                foreach (string a in actions.dup_strv()) {
                    var btn = new Button.with_label(a);
                    string action = a;
                    btn.clicked.connect(() => client.simple.begin("ActivateNotificationAction", new Variant("(sss)", device_id, key, action)));
                    buttons.append(btn);
                }
            }
            if (NearbyClient.flag_of(n, "clearable")) {
                var dismiss = new Button.with_label(_("Dismiss"));
                dismiss.clicked.connect(() => client.simple.begin("DismissNotification", new Variant("(ss)", device_id, key)));
                buttons.append(dismiss);
            }
            if (NearbyClient.flag_of(n, "can-reply")) {
                var reply_box = new Box(Orientation.HORIZONTAL, 6);
                var entry = new Entry();
                entry.hexpand = true;
                entry.placeholder_text = _("Reply");
                var send = new Button.from_icon_name("mail-send-symbolic");
                send.add_css_class("suggested-action");
                send.tooltip_text = _("Send Reply");
                send.update_property(AccessibleProperty.LABEL, _("Send Reply"), -1);
                send.sensitive = false;
                entry.changed.connect(() => send.sensitive = entry.text.strip() != "");
                send.clicked.connect(() => {
                    string msg = entry.text.strip();
                    if (msg == "") return;
                    client.simple.begin("ReplyNotification", new Variant("(sss)", device_id, key, msg));
                    entry.text = "";
                    entry.placeholder_text = _("Reply sent");
                });
                entry.activate.connect(() => send.clicked());
                reply_box.append(entry);
                reply_box.append(send);
                card.append(reply_box);
            }
            if (buttons.get_first_child() != null) card.append(buttons);
            return card;
        }
    }
}
