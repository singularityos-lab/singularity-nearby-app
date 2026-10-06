using Gtk;

namespace Singularity.Apps.Nearby {

    public delegate void FilesDropped(File[] files);

    public class DropZone : Box {
        private Label title;
        private Label hint;
        private Image icon;
        private Singularity.Animation.MotionBin bin;

        public signal void files_dropped(File[] files);
        public signal void browse();

        public DropZone() {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            var inner = new Box(Orientation.VERTICAL, 6);
            inner.add_css_class("nearby-drop");
            inner.margin_top = 2;
            inner.margin_bottom = 2;
            icon = new Image.from_icon_name("singularity-share-send-files");
            icon.pixel_size = 40;
            inner.append(icon);
            title = new Label("");
            title.add_css_class("heading");
            title.wrap = true;
            title.justify = Justification.CENTER;
            inner.append(title);
            hint = new Label(_("Or choose files to send"));
            hint.add_css_class("dim-label");
            hint.wrap = true;
            hint.justify = Justification.CENTER;
            inner.append(hint);
            bin = new Singularity.Animation.MotionBin(inner);
            append(bin);
            var click = new GestureClick();
            click.released.connect(() => browse());
            inner.add_controller(click);
            inner.cursor = new Gdk.Cursor.from_name("pointer", null);
            attach(inner, (files) => files_dropped(files), bin);
        }

        public void set_device_name(string name) {
            title.label = _("Drop Files Here to Send Them to %s").printf(name);
        }

        public static void attach(Widget target, owned FilesDropped callback, Singularity.Animation.MotionBin? bounce = null) {
            var drop = new DropTarget(typeof(Gdk.FileList), Gdk.DragAction.COPY);
            drop.enter.connect(() => {
                target.add_css_class("nearby-drop-hover");
                if (bounce != null) Singularity.Motion.spring_to(bounce, "scale", 1.02, Singularity.Motion.Spring.SNAPPY);
                return Gdk.DragAction.COPY;
            });
            drop.leave.connect(() => {
                target.remove_css_class("nearby-drop-hover");
                if (bounce != null) Singularity.Motion.spring_to(bounce, "scale", 1.0, Singularity.Motion.Spring.SNAPPY);
            });
            drop.drop.connect((value, x, y) => {
                target.remove_css_class("nearby-drop-hover");
                if (bounce != null) Singularity.Motion.spring_to(bounce, "scale", 1.0, Singularity.Motion.Spring.SNAPPY);
                var list = (Gdk.FileList) value.get_boxed();
                File[] files = {};
                foreach (var f in list.get_files()) files += f;
                if (files.length == 0) return false;
                callback(files);
                return true;
            });
            target.add_controller(drop);
        }
    }
}
