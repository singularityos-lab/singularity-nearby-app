namespace Singularity.Apps.Nearby {

    public class TransferItem : Object {
        public string id { get; construct; }
        public string device_id { get; set; default = ""; }
        public string batch { get; set; default = ""; }
        public string name { get; set; default = ""; }
        public bool incoming { get; set; default = false; }
        public int64 done { get; set; default = 0; }
        public int64 total { get; set; default = 0; }
        public string state { get; set; default = "running"; }
        public string detail { get; set; default = ""; }

        public TransferItem(string id) {
            Object(id: id);
        }

        public bool active {
            get { return state == "running" || state == "waiting"; }
        }

        public void update_from(Variant d) {
            device_id = NearbyClient.text_of(d, "device-id", device_id);
            batch = NearbyClient.text_of(d, "batch", batch);
            name = NearbyClient.text_of(d, "name", name);
            incoming = NearbyClient.flag_of(d, "incoming");
            done = NearbyClient.int_of(d, "done");
            total = NearbyClient.int_of(d, "total");
            state = NearbyClient.text_of(d, "state", state);
            detail = NearbyClient.text_of(d, "detail", "");
        }

        public string status() {
            return Format.transfer_status(state, incoming, done, total, detail);
        }
    }

    public class TransferStore : Object {
        public Gee.ArrayList<TransferItem> items { get; default = new Gee.ArrayList<TransferItem>(); }
        private NearbyClient? client;
        private uint reload_id = 0;

        public signal void changed();
        public signal void progress(TransferItem item);

        public TransferStore(NearbyClient? client) {
            this.client = client;
            if (client == null) return;
            client.transfer_started.connect((id, device, name, size, incoming) => {
                if (find(id) == null) {
                    var t = new TransferItem(id);
                    t.device_id = device;
                    t.name = name;
                    t.total = size;
                    t.incoming = incoming;
                    items.insert(0, t);
                    changed();
                }
                schedule_reload();
            });
            client.transfer_progress.connect((id, done, total) => apply_progress(id, done, total));
            client.transfer_finished.connect((id, ok, detail) => apply_finished(id, ok, detail));
            client.transfer_requested.connect(() => schedule_reload());
            client.notify["running"].connect(() => {
                if (client.running) reload.begin();
            });
            reload.begin();
        }

        public TransferItem? find(string id) {
            foreach (var t in items) if (t.id == id) return t;
            return null;
        }

        public Gee.List<TransferItem> for_device(string device_id) {
            var result = new Gee.ArrayList<TransferItem>();
            foreach (var t in items) if (t.device_id == device_id) result.add(t);
            return result;
        }

        public void apply_progress(string id, int64 done, int64 total) {
            var t = find(id);
            if (t == null) return;
            t.done = done;
            if (total > 0) t.total = total;
            if (t.state == "waiting" && !t.incoming) t.state = "running";
            progress(t);
        }

        public void apply_finished(string id, bool ok, string detail) {
            var t = find(id);
            if (t == null) return;
            t.state = ok ? "done" : "failed";
            t.detail = detail;
            if (ok && t.total > 0) t.done = t.total;
            changed();
            schedule_reload();
        }

        public void apply_list(Variant[] list) {
            var fresh = new Gee.ArrayList<TransferItem>();
            foreach (var d in list) {
                string id = NearbyClient.text_of(d, "id");
                if (id == "") continue;
                var t = find(id) ?? new TransferItem(id);
                t.update_from(d);
                fresh.add(t);
            }
            foreach (var t in items) {
                bool known = false;
                foreach (var f in fresh) if (f.id == t.id) known = true;
                if (!known && t.active) fresh.add(t);
            }
            items.clear();
            items.add_all(fresh);
            changed();
        }

        public void mark_batch(string batch, string state) {
            foreach (var t in items) if (t.batch == batch && t.state == "waiting") t.state = state;
            changed();
        }

        private void schedule_reload() {
            if (reload_id != 0) return;
            reload_id = Timeout.add(250, () => {
                reload_id = 0;
                reload.begin();
                return Source.REMOVE;
            });
        }

        public async void reload() {
            if (client == null) return;
            var list = yield client.list("GetTransfers");
            apply_list(list);
        }
    }
}
