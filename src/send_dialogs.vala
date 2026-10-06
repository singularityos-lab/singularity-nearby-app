using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Nearby {

    public delegate void DeviceChosen(string device_id);

    public class SendDialogs : Object {

        private static DropDown? device_picker(NearbyClient client, out string[] ids) {
            string[] names = {};
            string[] found = {};
            foreach (var d in client.usable_devices()) {
                if (!d.has_plugin("share")) continue;
                names += d.name;
                found += d.id;
            }
            ids = found;
            if (found.length < 2) return null;
            var drop = new DropDown.from_strings(names);
            drop.hexpand = true;
            return drop;
        }

        public static void pick_device(Gtk.Application app, NearbyClient client, string title, owned DeviceChosen chosen) {
            string[] ids;
            var picker = device_picker(client, out ids);
            if (ids.length == 0) {
                var dlg = new ConfirmDialog.message(app, _("No Device Connected"), "dev.sinty.Nearby",
                    _("Pair a phone or a computer and keep it on the same network to send it files and links."));
                dlg.present();
                return;
            }
            if (picker == null) {
                chosen(ids[0]);
                return;
            }
            var dlg = new ConfirmDialog(app, title, "dev.sinty.Nearby", _("Choose the device to send to."), _("Continue"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.custom_area.append(picker);
            dlg.response.connect((r) => {
                if (r == ConfirmDialog.Response.PRIMARY) chosen(ids[picker.selected]);
            });
            dlg.present();
        }

        public static void send_link(Gtk.Application app, NearbyClient client, string? device_id, string initial = "") {
            string[] ids = {};
            DropDown? picker = null;
            if (device_id == null || device_id == "") {
                picker = device_picker(client, out ids);
                if (ids.length == 0) {
                    pick_device(app, client, _("Send a Link"), (id) => {});
                    return;
                }
            }
            var target = client.find(device_id ?? (ids.length > 0 ? ids[0] : ""));
            string description = _("The link opens on the device you choose.");
            if (picker == null && target != null) description = _("The link opens on %s.").printf(target.name);
            var dlg = new ConfirmDialog(app, _("Send a Link"), "dev.sinty.Nearby", description, _("Send"), ConfirmDialog.ActionStyle.SUGGESTED);
            var entry = new Entry();
            entry.placeholder_text = "https://";
            entry.input_purpose = InputPurpose.URL;
            entry.text = initial;
            entry.hexpand = true;
            dlg.custom_area.append(entry);
            if (picker != null) dlg.custom_area.append(picker);
            dlg.primary_sensitive = initial.strip() != "";
            entry.changed.connect(() => dlg.primary_sensitive = entry.text.strip() != "");
            entry.activate.connect(() => {
                if (entry.text.strip() != "") {
                    dlg.response(ConfirmDialog.Response.PRIMARY);
                    dlg.close_dialog();
                }
            });
            dlg.response.connect((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                string id = picker != null ? ids[picker.selected] : (device_id ?? (ids.length > 0 ? ids[0] : ""));
                string text = entry.text.strip();
                if (id == "" || text == "") return;
                if (Format.is_link(Format.normalize_link(text))) {
                    client.simple.begin("ShareUrl", new Variant("(ss)", id, Format.normalize_link(text)));
                } else {
                    client.simple.begin("ShareText", new Variant("(ss)", id, text));
                }
            });
            dlg.present();
        }
    }
}
