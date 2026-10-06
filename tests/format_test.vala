using Singularity.Apps.Nearby;

string plain(string s) {
    return s.replace("\u00a0", " ");
}

void test_sizes() {
    assert(Format.size(0) == "0 bytes");
    assert(plain(Format.progress(500000, 1000000)) == "500.0 kB of 1.0 MB");
    assert(Format.fraction(1, 4) == 0.25);
    assert(Format.fraction(5, 0) == 0.0);
    assert(Format.fraction(9, 4) == 1.0);
}

void test_status() {
    assert(Format.transfer_status("waiting", true, 0, 10, "") == "Waiting for your answer");
    assert(plain(Format.transfer_status("running", false, 500000, 1000000, "")) == "Sending, 500.0 kB of 1.0 MB");
    assert(plain(Format.transfer_status("running", true, 500000, 1000000, "")) == "Receiving, 500.0 kB of 1.0 MB");
    assert(plain(Format.transfer_status("done", true, 1000000, 1000000, "/tmp/x")) == "Received, 1.0 MB");
    assert(Format.transfer_status("failed", false, 0, 0, "Pixel is no longer connected") == "Pixel is no longer connected");
    assert(Format.transfer_status("failed", false, 0, 0, "") == "Failed");
}

void test_codes_and_links() {
    assert(Format.pairing_code("a1b2c3d4") == "A1B2 C3D4");
    assert(Format.pairing_code("abc") == "ABC");
    assert(Format.first_address("Giulia, +39 333") == "Giulia");
    assert(Format.is_link("https://example.org/a?b=c"));
    assert(!Format.is_link("hello world"));
    assert(!Format.is_link("javascript:alert(1)"));
    assert(Format.normalize_link("example.org") == "https://example.org");
    assert(Format.normalize_link("https://x.y") == "https://x.y");
    assert(Format.device_icon("phone") == "phone");
    assert(Format.device_icon("tablet") == "phone");
    assert(Format.device_icon("laptop") == "computer");
    assert(Format.battery(64, false) == "64%");
    assert(Format.battery(64, true) == "64%, charging");
    assert(Format.battery(-1, false) == "");
}

void test_when() {
    int64 now = 1790620000;
    assert(Format.when(now - 10, now) == "Just now");
    assert(Format.when(now - 300, now) == "5 minutes ago");
    assert(Format.when(0, now) == "");
}

void test_store() {
    var store = new TransferStore(null);
    int changes = 0;
    store.changed.connect(() => changes++);
    var a = new VariantBuilder(new VariantType("a{sv}"));
    a.add("{sv}", "id", new Variant.string("t1"));
    a.add("{sv}", "device-id", new Variant.string("dev"));
    a.add("{sv}", "name", new Variant.string("photo.jpg"));
    a.add("{sv}", "incoming", new Variant.boolean(true));
    a.add("{sv}", "state", new Variant.string("waiting"));
    a.add("{sv}", "batch", new Variant.string("b1"));
    a.add("{sv}", "total", new Variant.int64(100));
    Variant[] list = { a.end() };
    store.apply_list(list);
    assert(store.items.size == 1);
    assert(store.for_device("dev").size == 1);
    assert(store.for_device("other").size == 0);
    var t = store.find("t1");
    assert(t.state == "waiting" && t.active);
    store.apply_progress("t1", 50, 100);
    assert(t.state == "waiting");
    store.mark_batch("b1", "running");
    assert(t.state == "running");
    store.apply_finished("t1", true, "/home/u/Downloads/photo.jpg");
    assert(t.state == "done" && t.done == 100 && !t.active);
    assert(t.detail == "/home/u/Downloads/photo.jpg");
    store.apply_list(new Variant[0]);
    assert(store.items.size == 0);
    assert(changes >= 3);
}

int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/nearby-app/sizes", test_sizes);
    Test.add_func("/nearby-app/status", test_status);
    Test.add_func("/nearby-app/codes-links", test_codes_and_links);
    Test.add_func("/nearby-app/when", test_when);
    Test.add_func("/nearby-app/store", test_store);
    return Test.run();
}
