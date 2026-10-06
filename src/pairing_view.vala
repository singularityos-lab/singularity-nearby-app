using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Nearby {

    public class PairingView : Box {
        private NearbyClient client;
        private Stack stack;
        private PreferencesGroup available_group;
        private EntryRow address_row;
        private Image device_icon;
        private Singularity.Animation.MotionBin icon_bin;
        private Label code_title;
        private Box code_box;
        private Label code_hint;
        private Button decline_btn;
        private Button accept_btn;
        private Button cancel_btn;
        private Image done_icon;
        private Singularity.Animation.MotionBin done_bin;
        private Label done_title;
        private string device_id = "";
        private string shown_code = "";
        private bool pulsing = false;
        private uint done_timeout = 0;
        private Gee.HashSet<string> listed = new Gee.HashSet<string>();

        public signal void paired(string device_id);
        public signal void device_chosen(string device_id);

        public PairingView(NearbyClient client) {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            this.client = client;
            stack = new Stack();
            stack.transition_type = StackTransitionType.CROSSFADE;
            stack.vexpand = true;
            stack.add_named(build_list(), "list");
            stack.add_named(build_code(), "code");
            stack.add_named(build_done(), "done");
            append(stack);
            client.changed.connect(() => sync());
            unmap.connect(() => pulsing = false);
        }

        private Widget scroller(Widget child) {
            var scroll = new ScrolledWindow();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.child = new Singularity.Widgets.Clamp(child, 620);
            return scroll;
        }

        private Widget build_list() {
            var page = new Box(Orientation.VERTICAL, 18);
            page.add_css_class("nearby-page");
            Singularity.Widgets.apply_titlebar_inset(page);
            var header = new Box(Orientation.VERTICAL, 6);
            var icon = new Image.from_icon_name("dev.sinty.Nearby");
            icon.pixel_size = 72;
            header.append(icon);
            var title = new Label(_("Pair a Device"));
            title.add_css_class("title-2");
            header.append(title);
            var hint = new Label(_("Open KDE Connect on the phone, or GSConnect on another computer, on the same network. Then pick it below."));
            hint.wrap = true;
            hint.justify = Justification.CENTER;
            hint.add_css_class("dim-label");
            header.append(hint);
            page.append(header);

            available_group = new PreferencesGroup(_("Available Devices"), _("Pair only with devices you know."));
            page.append(available_group);

            var address_group = new PreferencesGroup(_("Add by Address"), _("For a device the network hides from discovery."));
            address_row = new EntryRow(_("IP Address or Host Name"));
            var connect = new Button.with_label(_("Connect"));
            connect.valign = Align.CENTER;
            connect.clicked.connect(() => connect_address());
            address_row.add_suffix(connect);
            address_row.entry_activated.connect(() => connect_address());
            address_group.add_row(address_row);
            page.append(address_group);

            var get_app = new Button.with_label(_("Get KDE Connect for Your Phone"));
            get_app.add_css_class("pill");
            get_app.halign = Align.CENTER;
            get_app.clicked.connect(() => {
                try {
                    AppInfo.launch_default_for_uri("https://kdeconnect.kde.org/download.html", null);
                } catch (Error e) {
                    warning("nearby: %s", e.message);
                }
            });
            page.append(get_app);
            return scroller(page);
        }

        private Widget build_code() {
            var page = new Box(Orientation.VERTICAL, 18);
            page.add_css_class("nearby-page");
            page.valign = Align.CENTER;
            device_icon = new Image.from_icon_name("phone");
            device_icon.pixel_size = 96;
            icon_bin = new Singularity.Animation.MotionBin(device_icon);
            icon_bin.halign = Align.CENTER;
            page.append(icon_bin);
            code_title = new Label("");
            code_title.add_css_class("title-2");
            code_title.wrap = true;
            code_title.justify = Justification.CENTER;
            page.append(code_title);
            code_box = new Box(Orientation.HORIZONTAL, 6);
            code_box.halign = Align.CENTER;
            code_box.add_css_class("nearby-code");
            page.append(code_box);
            code_hint = new Label("");
            code_hint.wrap = true;
            code_hint.justify = Justification.CENTER;
            code_hint.add_css_class("dim-label");
            code_hint.max_width_chars = 44;
            page.append(code_hint);
            var buttons = new Box(Orientation.HORIZONTAL, 12);
            buttons.halign = Align.CENTER;
            buttons.margin_top = 6;
            decline_btn = new Button.with_label(_("Decline"));
            decline_btn.add_css_class("pill");
            decline_btn.width_request = 120;
            decline_btn.clicked.connect(() => client.simple.begin("RejectPair", new Variant("(s)", device_id)));
            buttons.append(decline_btn);
            cancel_btn = new Button.with_label(_("Cancel"));
            cancel_btn.add_css_class("pill");
            cancel_btn.width_request = 120;
            cancel_btn.clicked.connect(() => client.simple.begin("RejectPair", new Variant("(s)", device_id)));
            buttons.append(cancel_btn);
            accept_btn = new Button.with_label(_("Pair"));
            accept_btn.add_css_class("pill");
            accept_btn.add_css_class("suggested-action");
            accept_btn.width_request = 120;
            accept_btn.clicked.connect(() => on_accept());
            buttons.append(accept_btn);
            page.append(buttons);
            return scroller(page);
        }

        private Widget build_done() {
            var page = new Box(Orientation.VERTICAL, 14);
            page.add_css_class("nearby-page");
            page.valign = Align.CENTER;
            done_icon = new Image.from_icon_name("phone");
            done_icon.pixel_size = 96;
            var overlay = new Overlay();
            overlay.child = done_icon;
            var check = new Image.from_icon_name("object-select-symbolic");
            check.pixel_size = 22;
            check.add_css_class("nearby-check");
            check.halign = Align.END;
            check.valign = Align.END;
            overlay.add_overlay(check);
            done_bin = new Singularity.Animation.MotionBin(overlay);
            done_bin.halign = Align.CENTER;
            page.append(done_bin);
            done_title = new Label("");
            done_title.add_css_class("title-2");
            done_title.wrap = true;
            done_title.justify = Justification.CENTER;
            page.append(done_title);
            return scroller(page);
        }

        private void connect_address() {
            string a = address_row.text.strip();
            if (a == "") return;
            client.simple.begin("ConnectAddress", new Variant("(s)", a));
            address_row.text = "";
        }

        public void show_list() {
            device_id = "";
            stack.visible_child_name = "list";
            client.simple.begin("Refresh", null);
            sync();
        }

        public void show_device(string id) {
            device_id = id;
            shown_code = "";
            sync();
        }

        public string current_device {
            get { return device_id; }
        }

        private void sync() {
            if (device_id == "") {
                sync_list();
                return;
            }
            var d = client.find(device_id);
            if (d == null) {
                if (stack.visible_child_name != "done") show_list();
                return;
            }
            if (d.paired) {
                if (stack.visible_child_name == "code") celebrate(d);
                else if (stack.visible_child_name != "done") paired(d.id);
                return;
            }
            if (d.pair_state == "none" && stack.visible_child_name == "code" && shown_code != "") {
                show_list();
                return;
            }
            device_icon.icon_name = Format.device_icon(d.device_type);
            bool incoming = d.pair_state == "incoming";
            bool requested = d.pair_state == "requested";
            decline_btn.visible = incoming;
            accept_btn.visible = incoming || (!requested && d.reachable);
            accept_btn.label = incoming ? _("Pair") : _("Request Pairing");
            cancel_btn.visible = requested;
            if (incoming) {
                code_title.label = _("%s Wants to Pair").printf(d.name);
                code_hint.label = _("Pair only if %s shows the same code.").printf(d.name);
            } else if (requested) {
                code_title.label = _("Pairing with %s").printf(d.name);
                code_hint.label = _("Accept on %s if it shows the same code.").printf(d.name);
            } else {
                code_title.label = d.name;
                code_hint.label = d.reachable ? _("Ask %s to pair. Both devices will show a code to compare.").printf(d.name)
                    : _("%s is not nearby. Open KDE Connect on it.").printf(d.name);
            }
            set_code(d.verification);
            stack.visible_child_name = "code";
            start_pulse();
        }

        private void on_accept() {
            var d = client.find(device_id);
            if (d == null) return;
            if (d.pair_state == "incoming") client.simple.begin("AcceptPair", new Variant("(s)", device_id));
            else client.simple.begin("RequestPair", new Variant("(s)", device_id));
        }

        private void set_code(string code) {
            if (code == shown_code) return;
            shown_code = code;
            var child = code_box.get_first_child();
            while (child != null) {
                var next = child.get_next_sibling();
                code_box.remove(child);
                child = next;
            }
            code_box.visible = code != "";
            if (code == "") return;
            string text = Format.pairing_code(code);
            Widget[] cells = {};
            for (int i = 0; i < text.char_count(); i++) {
                unichar c = text.get_char(text.index_of_nth_char(i));
                if (c == ' ') {
                    var gap = new Box(Orientation.HORIZONTAL, 0);
                    gap.width_request = 10;
                    code_box.append(gap);
                    continue;
                }
                var cell = new Label(c.to_string());
                cell.add_css_class("nearby-code-cell");
                cell.add_css_class("numeric");
                var bin = new Singularity.Animation.MotionBin(cell);
                code_box.append(bin);
                cells += bin;
            }
            code_box.update_property(AccessibleProperty.LABEL, _("Code %s").printf(text), -1);
            Singularity.Motion.cascade(cells, Singularity.Motion.Preset.FADE_SLIDE);
        }

        private void start_pulse() {
            if (pulsing || Singularity.Motion.reduced()) return;
            pulsing = true;
            pulse_step(true);
        }

        private void pulse_step(bool grow) {
            if (!pulsing || stack.visible_child_name != "code" || !get_mapped()) {
                pulsing = false;
                icon_bin.scale = 1.0;
                return;
            }
            var anim = Singularity.Motion.tween(icon_bin, "scale", grow ? 1.06 : 1.0,
                Singularity.Motion.Duration.SCENE, Singularity.Motion.Curve.STANDARD);
            anim.done.connect(() => pulse_step(!grow));
        }

        private void celebrate(NearbyDevice d) {
            pulsing = false;
            icon_bin.scale = 1.0;
            done_icon.icon_name = Format.device_icon(d.device_type);
            done_title.label = _("Paired with %s").printf(d.name);
            stack.visible_child_name = "done";
            Singularity.Motion.reveal(done_bin, Singularity.Motion.Preset.SCALE_FADE);
            if (done_timeout != 0) Source.remove(done_timeout);
            string id = d.id;
            done_timeout = Timeout.add(1200, () => {
                done_timeout = 0;
                paired(id);
                return Source.REMOVE;
            });
        }

        private void sync_list() {
            available_group.clear();
            var others = new Gee.ArrayList<NearbyDevice>();
            foreach (var d in client.devices) if (!d.paired && d.reachable) others.add(d);
            if (others.size == 0) {
                var row = new ActionRow(_("Looking for Devices…"), _("Keep KDE Connect open on the phone."));
                var spinner = new Spinner();
                spinner.spinning = true;
                spinner.valign = Align.CENTER;
                row.add_suffix(spinner);
                available_group.add_row(row);
            }
            Widget[] fresh = {};
            foreach (var d in others) {
                var row = new ActionRow(d.name, d.status_text(), d.icon_name);
                string id = d.id;
                var pair = new Button.with_label(d.pair_state == "incoming" ? _("Review") : _("Pair"));
                pair.valign = Align.CENTER;
                pair.add_css_class("suggested-action");
                pair.clicked.connect(() => {
                    device_chosen(id);
                    var dev = client.find(id);
                    if (dev != null && dev.pair_state == "none") client.simple.begin("RequestPair", new Variant("(s)", id));
                });
                row.add_suffix(pair);
                available_group.add_row(row);
                if (!listed.contains(id)) fresh += row;
            }
            listed.clear();
            foreach (var d in others) listed.add(d.id);
            if (fresh.length > 0) Singularity.Motion.cascade(fresh, Singularity.Motion.Preset.FADE);
        }
    }
}
