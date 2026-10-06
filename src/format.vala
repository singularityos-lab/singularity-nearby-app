namespace Singularity.Apps.Nearby {

    public class Format : Object {

        public static string size(int64 bytes) {
            return GLib.format_size((uint64) int64.max(0, bytes));
        }

        public static string progress(int64 done, int64 total) {
            if (total <= 0) return size(done);
            return _("%s of %s").printf(size(done), size(total));
        }

        public static double fraction(int64 done, int64 total) {
            if (total <= 0) return 0.0;
            return double.min(1.0, double.max(0.0, (double) done / (double) total));
        }

        public static string transfer_status(string state, bool incoming, int64 done, int64 total, string detail) {
            switch (state) {
                case "waiting":
                    return _("Waiting for your answer");
                case "done":
                    int64 amount = total > 0 ? total : done;
                    if (incoming) return _("Received, %s").printf(size(amount));
                    return _("Sent, %s").printf(size(amount));
                case "failed":
                    return detail != "" ? detail : _("Failed");
                default:
                    if (incoming) return _("Receiving, %s").printf(progress(done, total));
                    return _("Sending, %s").printf(progress(done, total));
            }
        }

        public static string when(int64 unix_seconds, int64 now_seconds) {
            if (unix_seconds <= 0) return "";
            int64 diff = now_seconds - unix_seconds;
            if (diff < 60) return _("Just now");
            if (diff < 3600) {
                int m = (int) (diff / 60);
                return ngettext("%d minute ago", "%d minutes ago", m).printf(m);
            }
            var then = new DateTime.from_unix_local(unix_seconds);
            var now = new DateTime.from_unix_local(now_seconds);
            if (then.get_year() == now.get_year() && then.get_day_of_year() == now.get_day_of_year()) {
                return then.format("%H:%M");
            }
            if (diff < 7 * 86400) return then.format("%a %H:%M");
            return then.format("%e %b %Y").strip();
        }

        public static string battery(int level, bool charging) {
            if (level < 0) return "";
            if (charging) return _("%d%%, charging").printf(level);
            return _("%d%%").printf(level);
        }

        public static string device_icon(string device_type) {
            switch (device_type) {
                case "phone":
                case "smartphone":
                case "tablet":
                    return "phone";
                default:
                    return "computer";
            }
        }

        public static string pairing_code(string code) {
            string c = code.strip().up();
            if (c.length == 8) return c.substring(0, 4) + " " + c.substring(4, 4);
            return c;
        }

        public static string first_address(string addresses) {
            return addresses.split(",")[0].strip();
        }

        public static bool is_link(string text) {
            string t = text.strip();
            if (t == "" || t.contains(" ") || t.contains("\n")) return false;
            string? scheme = Uri.peek_scheme(t);
            return scheme != null && (scheme == "http" || scheme == "https" || scheme == "mailto" || scheme == "tel" || scheme == "geo");
        }

        public static string normalize_link(string text) {
            string t = text.strip();
            if (Uri.peek_scheme(t) == null && t.contains(".") && !t.contains(" ")) return "https://" + t;
            return t;
        }
    }
}
