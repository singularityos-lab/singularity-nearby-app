namespace Singularity.Apps.Nearby {

    public class NearbySearch : Singularity.SearchProviderService {
        private NearbyApp app;

        public NearbySearch(NearbyApp app) {
            this.app = app;
        }

        private async void ready() {
            app.touch();
            if (app.client.devices.size == 0 && app.client.available) yield app.client.refresh();
        }

        private static bool matches(NearbyDevice d, string[] terms) {
            string haystack = (d.name + " " + d.device_type + " " + _("phone") + " nearby").down();
            foreach (string t in terms) {
                if (!haystack.contains(t.down())) return false;
            }
            return true;
        }

        private string[] find(string[] terms, string[]? within) {
            string[] ids = {};
            foreach (var d in app.client.devices) {
                if (!d.paired) continue;
                if (within != null && !(d.id in within)) continue;
                if (matches(d, terms)) ids += d.id;
            }
            return ids;
        }

        public override async string[] get_initial_results(string[] terms, Cancellable? cancellable) throws Error {
            yield ready();
            return find(terms, null);
        }

        public override async string[] get_subsearch_results(string[] previous, string[] terms, Cancellable? cancellable) throws Error {
            yield ready();
            return find(terms, previous);
        }

        public override async Singularity.SearchResultMeta[] get_result_metas(string[] ids, Cancellable? cancellable) throws Error {
            app.touch();
            Singularity.SearchResultMeta[] metas = {};
            foreach (string id in ids) {
                var d = app.client.find(id);
                if (d == null) continue;
                var meta = new Singularity.SearchResultMeta(id, d.name);
                meta.description = d.status_text();
                meta.icon = new ThemedIcon(Format.device_icon(d.device_type));
                if (d.usable && d.has_plugin("share")) meta.add_action("send", _("Send Files"), "document-send-symbolic");
                if (d.usable && d.has_plugin("findmyphone") && d.supports_find) meta.add_action("ring", _("Ring"), "audio-volume-high-symbolic");
                metas += meta;
            }
            return metas;
        }

        public override async Singularity.SearchActivationReply? activate_result(string id, string[] terms, uint32 timestamp) throws Error {
            app.present_device(id, null);
            return null;
        }

        public override async Singularity.SearchActivationReply? activate_action(string id, string action_id, string[] terms, uint32 timestamp) throws Error {
            if (action_id == "ring") {
                app.touch();
                yield app.client.simple("Ring", new Variant("(s)", id));
                return null;
            }
            app.present_device(id, "send-files");
            return null;
        }

        public override void launch_search(string[] terms, uint32 timestamp) {
            app.present_device(null, null);
        }
    }
}
