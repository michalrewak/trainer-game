"""Wybór trenażera spośród zeskanowanych urządzeń i tabela skanera."""

from wasteland_bridge.devices import DeviceInfo, DeviceSelector, normalize_uuid, sort_for_display
from wasteland_bridge.ftms import FTMS_SERVICE_UUID
from wasteland_bridge.scan import device_rows

HR_SERVICE = "0000180d-0000-1000-8000-00805f9b34fb"

SUITO = DeviceInfo.create("D4:1A:2B:3C:4D:5E", "SUITO 12345", -61, ["1826", "1818"])
KICKR = DeviceInfo.create("C0:FF:EE:00:00:01", "KICKR CORE 1A2B", -48, [FTMS_SERVICE_UUID])
HRM = DeviceInfo.create("AA:00:00:00:00:02", "HRM-Pro", -40, [HR_SERVICE])
TV = DeviceInfo.create("AA:00:00:00:00:03", None, -70, [])


def test_normalize_uuid_forms():
    assert normalize_uuid("1826") == FTMS_SERVICE_UUID
    assert normalize_uuid("0x1826") == FTMS_SERVICE_UUID
    assert normalize_uuid(FTMS_SERVICE_UUID.upper()) == FTMS_SERVICE_UUID
    assert SUITO.has_ftms and KICKR.has_ftms and not HRM.has_ftms


def test_default_prefers_suito_by_name():
    choice = DeviceSelector().choose([HRM, KICKR, SUITO, TV])
    assert choice is not None
    device, reason = choice
    assert device is SUITO
    assert "SUITO" in reason


def test_name_match_is_case_insensitive_and_prefers_stronger_signal():
    weak = DeviceInfo.create("01:01:01:01:01:01", "Suito-T", -90, ["1826"])
    device, _ = DeviceSelector(name="suito").choose([weak, SUITO])
    assert device is SUITO


def test_fallback_to_any_ftms_when_name_not_found():
    device, reason = DeviceSelector(name="SUITO").choose([HRM, KICKR])
    assert device is KICKR
    assert "brak urządzenia" in reason


def test_empty_name_means_first_ftms_device():
    selector = DeviceSelector(name="")
    assert selector.name is None
    device, _ = selector.choose([HRM, SUITO, KICKR])
    assert device is KICKR  # najsilniejszy sygnał
    assert selector.is_definite_match(SUITO)
    assert not selector.is_definite_match(HRM)


def test_address_is_exact_and_has_no_fallback():
    selector = DeviceSelector(address="d4:1a:2b:3c:4d:5e")
    device, _ = selector.choose([KICKR, SUITO])
    assert device is SUITO
    assert DeviceSelector(address="11:22:33:44:55:66").choose([KICKR, SUITO]) is None
    assert selector.is_definite_match(SUITO)
    assert not selector.is_definite_match(KICKR)


def test_preferred_address_wins_after_reconnect():
    selector = DeviceSelector(name="SUITO")
    device, reason = selector.choose([SUITO, KICKR], preferred_address=KICKR.address)
    assert device is KICKR
    assert "ostatnio" in reason
    assert selector.is_definite_match(KICKR, KICKR.address.lower())


def test_nothing_suitable():
    assert DeviceSelector().choose([HRM, TV]) is None
    assert DeviceSelector().choose([]) is None


def test_merged_advertisements_keep_name_and_union_uuids():
    first = DeviceInfo.create("AB:CD:00:00:00:01", None, -70, ["1826"])
    later = DeviceInfo.create("AB:CD:00:00:00:01", "SUITO 9", None, ["180a"])
    merged = first.merged(later)
    assert merged.name == "SUITO 9"
    assert merged.rssi == -70
    assert merged.has_ftms
    assert len(merged.service_uuids) == 2
    assert later.merged(DeviceInfo.create("AB:CD:00:00:00:01", None, -50, [])).name == "SUITO 9"


def test_display_order_and_rows():
    ordered = sort_for_display([TV, HRM, SUITO, KICKR])
    assert ordered[:2] == [KICKR, SUITO]
    rows = device_rows([TV, SUITO])
    assert rows[0] == ("SUITO 12345", "D4:1A:2B:3C:4D:5E", "-61 dBm", "TAK – trenażer")
    assert rows[1][0] == "(bez nazwy)" and rows[1][3] == ""
