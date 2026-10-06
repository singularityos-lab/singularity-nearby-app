using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Nearby {

    public class MessagesView : Box {
        private NearbyClient client;
        private string device_id = "";
        private int64 thread = -1;
        private string thread_address = "";
        private ListBox list;
        private Stack thread_stack;
        private StatusPage empty;
        private Label thread_title;
        private Box bubbles;
        private ScrolledWindow bubble_scroll;
        private Entry to_entry;
        private Box to_box;
        private Entry composer;
        private Button send_btn;
        private Gee.HashSet<string> seen = new Gee.HashSet<string>();

        public MessagesView(NearbyClient client) {
            Object(orientation: Orientation.HORIZONTAL, spacing: 0);
            this.client = client;

            var left = new Box(Orientation.VERTICAL, 0);
            left.width_request = 280;
            left.add_css_class("nearby-conversations");
            list = new ListBox();
            list.selection_mode = SelectionMode.SINGLE;
            list.add_css_class("navigation-sidebar");
            Singularity.Widgets.apply_titlebar_inset(list);
            list.row_activated.connect((row) => {
                var r = row as ConversationRow;
                if (r != null) open_thread(r.thread, r.address);

            });
            var list_scroll = new ScrolledWindow();
            list_scroll.hscrollbar_policy = PolicyType.NEVER;
            list_scroll.vexpand = true;
            list_scroll.child = list;
            left.append(list_scroll);
            append(left);
            append(new Separator(Orientation.VERTICAL));

            thread_stack = new Stack();
            thread_stack.hexpand = true;
            thread_stack.transition_type = StackTransitionType.CROSSFADE;
            empty = new StatusPage();
            empty.icon_name = "singularity-share-message";
            empty.title = _("No Conversation Selected");
            empty.description = _("Pick a conversation, or start a new message.");
            var start = new Button.with_label(_("New Message"));
            start.add_css_class("pill");
            start.add_css_class("suggested-action");
            start.halign = Align.CENTER;
            start.clicked.connect(() => new_message());
            empty.child = start;
            thread_stack.add_named(empty, "empty");

            var thread_box = new Box(Orientation.VERTICAL, 0);
            thread_title = new Label("");
            thread_title.add_css_class("heading");
            thread_title.margin_top = 20;
            thread_title.margin_bottom = 8;
            thread_title.ellipsize = Pango.EllipsizeMode.END;
            thread_box.append(thread_title);
            to_box = new Box(Orientation.HORIZONTAL, 8);
            to_box.margin_start = 16;
            to_box.margin_end = 16;
            to_box.margin_bottom = 8;
            var to_label = new Label(_("To"));
            to_label.add_css_class("dim-label");
            to_box.append(to_label);
            to_entry = new Entry();
            to_entry.hexpand = true;
            to_entry.placeholder_text = _("Phone Number");
            to_entry.input_purpose = InputPurpose.PHONE;
            to_entry.changed.connect(() => update_send());
            to_box.append(to_entry);
            thread_box.append(to_box);
            bubbles = new Box(Orientation.VERTICAL, 6);
            bubbles.margin_top = 8;
            bubbles.margin_bottom = 8;
            bubbles.valign = Align.END;
            bubble_scroll = new ScrolledWindow();
            bubble_scroll.hscrollbar_policy = PolicyType.NEVER;
            bubble_scroll.vexpand = true;
            bubble_scroll.child = new Singularity.Widgets.Clamp(bubbles, 640);
            thread_box.append(bubble_scroll);
            var compose_box = new Box(Orientation.HORIZONTAL, 8);
            compose_box.add_css_class("nearby-composer");
            composer = new Entry();
            composer.hexpand = true;
            composer.placeholder_text = _("Text Message");
            composer.changed.connect(() => update_send());
            composer.activate.connect(() => send());
            compose_box.append(composer);
            send_btn = new Button.from_icon_name("mail-send-symbolic");
            send_btn.add_css_class("suggested-action");
            send_btn.add_css_class("circular");
            send_btn.tooltip_text = _("Send");
            send_btn.update_property(AccessibleProperty.LABEL, _("Send"), -1);
            send_btn.clicked.connect(() => send());
            compose_box.append(send_btn);
            thread_box.append(compose_box);
            thread_stack.add_named(thread_box, "thread");
            append(thread_stack);

            client.conversations_changed.connect((id) => {
                if (id != device_id) return;
                fill_list.begin();
                if (thread >= 0) fill_thread.begin();
            });
            update_send();
        }

        public void show_device(string id) {
            if (id != device_id) {
                device_id = id;
                thread = -1;
                seen.clear();
                thread_stack.visible_child_name = "empty";
            }
            client.simple.begin("RequestConversations", new Variant("(s)", id));
            fill_list.begin();
        }

        public void new_message() {
            thread = -1;
            thread_address = "";
            list.unselect_all();
            thread_title.label = _("New Message");
            to_box.visible = true;
            to_entry.text = "";
            clear_bubbles();
            thread_stack.visible_child_name = "thread";
            to_entry.grab_focus();
            update_send();
        }

        private void open_thread(int64 t, string address) {
            thread = t;
            thread_address = address;
            thread_title.label = address;
            to_box.visible = false;
            thread_stack.visible_child_name = "thread";
            client.simple.begin("RequestConversation", new Variant("(sx)", device_id, t));
            fill_thread.begin();
            composer.grab_focus();
            update_send();
        }

        private void update_send() {
            bool has_to = to_box.visible ? to_entry.text.strip() != "" : thread_address != "";
            send_btn.sensitive = has_to && composer.text.strip() != "";
        }

        private void send() {
            if (!send_btn.sensitive) return;
            string to = to_box.visible ? to_entry.text.strip() : Format.first_address(thread_address);
            string body = composer.text.strip();
            client.simple.begin("SendSms", new Variant("(sss)", device_id, to, body));
            append_bubble(body, true, true);
            composer.text = "";
        }

        private async void fill_list() {
            var convs = yield client.list("GetConversations", new Variant("(s)", device_id));
            var child = list.get_first_child();
            while (child != null) {
                var next = child.get_next_sibling();
                list.remove(child);
                child = next;
            }
            Widget[] fresh = {};
            foreach (var m in convs) {
                var row = new ConversationRow(m);
                list.append(row);
                if (row.thread == thread) list.select_row(row);
                if (!seen.contains(row.thread.to_string())) fresh += row;
                seen.add(row.thread.to_string());
            }
            if (convs.length == 0) {
                var loading = new ListBoxRow();
                loading.activatable = false;
                loading.selectable = false;
                var l = new Label(_("Loading conversations. Keep the phone unlocked the first time."));
                l.wrap = true;
                l.add_css_class("dim-label");
                l.margin_top = 12;
                l.margin_start = 8;
                l.margin_end = 8;
                l.xalign = 0;
                loading.child = l;
                list.append(loading);
            }
            if (fresh.length > 0) Singularity.Motion.cascade(fresh, Singularity.Motion.Preset.FADE);
        }

        private void clear_bubbles() {
            var child = bubbles.get_first_child();
            while (child != null) {
                var next = child.get_next_sibling();
                bubbles.remove(child);
                child = next;
            }
        }

        private async void fill_thread() {
            if (thread < 0) return;
            var msgs = yield client.list("GetMessages", new Variant("(sx)", device_id, thread));
            clear_bubbles();
            int start = int.max(0, msgs.length - 60);
            for (int i = start; i < msgs.length; i++) {
                append_bubble(NearbyClient.text_of(msgs[i], "body"), NearbyClient.flag_of(msgs[i], "outgoing"), false);
            }
            Idle.add(() => {
                var adj = bubble_scroll.vadjustment;
                adj.value = adj.upper;
                return Source.REMOVE;
            });
        }

        private void append_bubble(string text, bool mine, bool animate) {
            var label = new Label(text);
            label.wrap = true;
            label.wrap_mode = Pango.WrapMode.WORD_CHAR;
            label.xalign = 0;
            label.max_width_chars = 40;
            label.selectable = true;
            label.margin_top = 8;
            label.margin_bottom = 8;
            label.margin_start = 12;
            label.margin_end = 12;
            var bubble = new Box(Orientation.VERTICAL, 0);
            bubble.add_css_class("nearby-bubble");
            if (mine) bubble.add_css_class("mine");
            bubble.append(label);
            var bin = new Singularity.Animation.MotionBin(bubble);
            bin.halign = mine ? Align.END : Align.START;
            bin.margin_start = 16;
            bin.margin_end = 16;
            bubbles.append(bin);
            if (animate) Singularity.Motion.reveal(bin, Singularity.Motion.Preset.FADE_SLIDE);
        }
    }

    public class ConversationRow : ListBoxRow {
        public int64 thread;
        public string address;

        public ConversationRow(Variant m) {
            thread = NearbyClient.int_of(m, "thread");
            address = NearbyClient.text_of(m, "address");
            string body = NearbyClient.text_of(m, "body");
            if (NearbyClient.flag_of(m, "outgoing")) body = _("You: %s").printf(body);
            bool unread = !NearbyClient.flag_of(m, "read");
            var box = new Box(Orientation.HORIZONTAL, 10);
            box.margin_top = 8;
            box.margin_bottom = 8;
            box.margin_start = 6;
            box.margin_end = 6;
            string initial = "#";
            if (address.strip() != "") initial = address.strip().get_char(0).to_string().up();
            var avatar = new Label(initial.get_char(0).isalpha() ? initial : "#");
            avatar.add_css_class("nearby-avatar");
            avatar.valign = Align.CENTER;
            box.append(avatar);
            var col = new Box(Orientation.VERTICAL, 2);
            col.hexpand = true;
            var top = new Box(Orientation.HORIZONTAL, 6);
            var name = new Label(address);
            name.xalign = 0;
            name.hexpand = true;
            name.ellipsize = Pango.EllipsizeMode.END;
            if (unread) name.add_css_class("heading");
            top.append(name);
            var when = new Label(Format.when(NearbyClient.int_of(m, "date") / 1000, get_real_time() / 1000000));
            when.add_css_class("dim-label");
            when.add_css_class("caption");
            top.append(when);
            col.append(top);
            var preview = new Label(body);
            preview.xalign = 0;
            preview.ellipsize = Pango.EllipsizeMode.END;
            preview.add_css_class(unread ? "caption-heading" : "dim-label");
            preview.add_css_class("caption");
            col.append(preview);
            box.append(col);
            child = box;
        }
    }
}
