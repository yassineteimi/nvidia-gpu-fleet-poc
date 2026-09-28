import pytest

from remediator import xid

LINE_79 = ("NVRM: Xid (PCI:0000:01:00): 79, pid='<unknown>', name=<unknown>, "
           "GPU has fallen off the bus.")


def test_parses_pci_address_and_code():
    assert xid.parse(LINE_79) == ("0000:01:00", 79)


@pytest.mark.parametrize("line, expected", [
    # The three shapes of the driver's format string at 595.91.07.
    ("NVRM: Xid (PCI:0000:01:00): 79, pid=1234, name=python3, GPU has fallen off the bus.", ("0000:01:00", 79)),
    ("NVRM: Xid (PCI:0000:01:00): 48, An uncorrectable double bit error", ("0000:01:00", 48)),
    ("NVRM: Xid (PCI:0000:3b:00 GPU-I:01 GPU-CI:02): 13, pid=9, name=a, Graphics Exception", ("0000:3b:00", 13)),
])
def test_every_shape_the_driver_prints(line, expected):
    assert xid.parse(line) == expected


def test_takes_the_last_xid_when_several_lines_are_joined():
    joined = "NVRM: Xid (PCI:0000:01:00): 13, pid=1, x\n" + LINE_79
    assert xid.parse(joined) == ("0000:01:00", 79)


@pytest.mark.parametrize("message", ["", None, "NVRM: GPU at PCI:0000:01:00: GPU-1234", "Xid 79"])
def test_returns_none_for_anything_that_is_not_an_xid_line(message):
    assert xid.parse(message) is None


@pytest.mark.parametrize("code", [13, 31, 43, 45, 68, 109])
def test_the_device_plugin_application_errors_are_not_faults(code):
    assert not xid.is_fault(code)


@pytest.mark.parametrize("code", [48, 62, 63, 64, 74, 79, 92, 94, 95, 119, 120, 999])
def test_everything_else_is_a_fault(code):
    assert xid.is_fault(code)


def test_describe_names_known_codes_and_only_numbers_unknown_ones():
    assert xid.describe(79) == "XID 79 (GPU has fallen off the bus)"
    assert xid.describe(1234) == "XID 1234"
