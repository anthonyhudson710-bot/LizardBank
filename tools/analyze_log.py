#!/usr/bin/env python3
"""Summarize Lizard Bank evidence; never certify native or real-world accuracy.

Only the Python standard library is required. The original log remains the
authoritative evidence: report references use its physical line numbers and
the logger's process-local sequence numbers. Lua numeric-key tables are JSON
objects, not arrays. No Lua or code embedded in a log/catalog is executed.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import sys


PREFIX = "[LizardBank:VALIDATION]"
OUTCOMES = ("PASS", "FAIL", "WARN", "UNAVAILABLE", "NOT_EXERCISED")
ORIGINS = ("runtime", "synthetic", "unspecified")
CATALOG_PATH = Path(__file__).resolve().parents[1] / "scripts" / "BankValidationCatalog.lua"
NATIVE_WARNING = re.compile(r"\b(?:Error|Warning|LUA call stack|Call Stack)\b", re.I)
CATALOG_ROW = re.compile(
    r'\{\s*id\s*=\s*"(?P<id>[A-Z]+-\d+)"\s*,\s*group\s*=\s*"(?P<group>[A-Z]+)"'
    r'\s*,\s*evidence\s*=\s*"(?P<evidence>[a-z]+)"\s*,'
    r'\s*description\s*=\s*(?P<description>"(?:[^"\\]|\\.)*")', re.S)
CAPABILITY_PATH = re.compile(r'^snapshot\["capabilities"\](?:\[.*\])?$')
GATE_PATH = re.compile(r'^snapshot\["(?:finance|history|underwriting)"\]')
HISTORY_EVENTS = {"history.transaction.begin", "history.transaction.end", "history.save.begin",
                  "history.save.end", "history.native.begin", "history.native.return", "history.native.error",
                  "history.save.sidecar.begin"}
MAX_HISTORY_CALLS = 120000


def integer(value):
    return isinstance(value, int) and not isinstance(value, bool)


def reject_constant(value):
    raise ValueError("Non-JSON numeric constant: " + value)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON object key: " + key)
        result[key] = value
    return result


def load_catalog(path=CATALOG_PATH):
    """Strictly extract the known declarative layout; never evaluate Lua."""
    result = {"source": str(path), "status": "unavailable", "checks": []}
    try:
        source = Path(path).read_text(encoding="utf-8")
        for match in CATALOG_ROW.finditer(source):
            row = match.groupdict()
            row["description"] = json.loads(row["description"])
            result["checks"].append(row)
        declared = len(re.findall(r'\{\s*id\s*=', source))
        ids = [row["id"] for row in result["checks"]]
        if declared and declared == len(ids) == len(set(ids)):
            result["status"] = "available"
        else:
            result["status"] = "partial"
            result["error"] = "Catalog layout not fully recognized; scenario coverage is incomplete."
    except (OSError, UnicodeError, ValueError) as error:
        result["error"] = str(error)
    return result


def reference(line, record=None):
    record = record or {}
    return {"line": line, "seq": record.get("seq"), "capture": record.get("capture"),
            "event": record.get("event"), "origin": record.get("origin", "unspecified")}


def problem(target, code, message, ref=None):
    target["problems"].append({"code": code, "message": message, **(ref or {})})


def new_mission(run, mission_id):
    return {"run": run, "mission": mission_id, "problems": [], "checks": {},
            "captures": [], "dumps": [], "eventCounts": {origin: Counter() for origin in ORIGINS},
            "failureEvidence": [], "availabilityEvidence": [], "manualComparisons": [], "latestCapabilities": {},
            "latestGates": {}, "summaryCoverage": {}, "began": False, "ended": False,
            "summaries": 0, "lastSummaryLine": None, "lastCheckLine": None, "lastActivityLine": None,
            "_openCaptures": {}, "_openDumps": {}, "_summary": None,
            "_transactionIds": {origin: set() for origin in ORIGINS},
            "_saveIds": {origin: set() for origin in ORIGINS}, "_historyCalls": {}, "_historyLimited": False}


def read_history_call(mission, event, data, origin, ref):
    """Correlate existing observer IDs without assuming each save-end is a save.

    This proves transport ordering only. The observer's invocation trace cannot
    establish that the engine completed its whole save or had no hidden effects.
    """
    if event not in HISTORY_EVENTS:
        return
    identity = data.get("transactionId")
    if not integer(identity) or identity < 1:
        problem(mission, "HISTORY_ID_UNAVAILABLE", "History event lacks a positive transaction ID; lifecycle cannot be correlated.", ref)
        return
    key = (origin, identity)
    calls = mission["_historyCalls"]
    if key not in calls:
        if len(calls) >= MAX_HISTORY_CALLS:
            if not mission["_historyLimited"]:
                problem(mission, "HISTORY_CORRELATION_LIMIT", "History correlation exceeded its bounded ID budget; later lifecycles are unverified.", ref)
                mission["_historyLimited"] = True
            return
        calls[key] = {"id": identity, "origin": origin, "first": ref, "begin": None, "end": None,
                      "nativeBegin": None, "nativeEnd": None, "kind": None, "sidecars": {}, "valid": True}
    row = calls[key]

    def reject(code, message):
        row["valid"] = False
        problem(mission, code, "History ID %s (%s): %s" % (identity, origin, message), ref)

    if event in ("history.transaction.begin", "history.save.begin"):
        if row["begin"] is not None:
            reject("HISTORY_DUPLICATE_BEGIN", "observer begin was recorded more than once.")
            return
        row["begin"], row["kind"] = ref, "save" if event == "history.save.begin" else "transaction"
        parent_id = data.get("parentTransactionId")
        if parent_id is not None:
            parent = calls.get((origin, parent_id)) if integer(parent_id) else None
            if parent_id == identity or parent is None or parent["begin"] is None or parent["end"] is not None:
                reject("HISTORY_PARENT_UNAVAILABLE", "nested call has no active captured parent in the same origin.")
        return
    if row["begin"] is None:
        reject("HISTORY_EVENT_WITHOUT_BEGIN", "event has no captured observer begin.")
    if row["end"] is not None:
        reject("HISTORY_EVENT_AFTER_END", "event followed the terminal observer end.")
    if event == "history.native.begin":
        if row["nativeBegin"] is not None:
            reject("HISTORY_DUPLICATE_NATIVE_BEGIN", "more than one native invocation began for this observer ID.")
        row["nativeBegin"] = ref
    elif event in ("history.native.return", "history.native.error"):
        if row["nativeBegin"] is None:
            reject("HISTORY_NATIVE_RESULT_WITHOUT_BEGIN", "native result has no invocation begin.")
        if row["nativeEnd"] is not None:
            reject("HISTORY_DUPLICATE_NATIVE_RESULT", "native invocation has multiple result events.")
        row["nativeEnd"], row["nativeSucceeded"] = ref, event == "history.native.return"
        if data.get("nativeCallCount") != 1 or isinstance(data.get("nativeCallCount"), bool):
            reject("HISTORY_NATIVE_CALL_COUNT", "native result does not declare exactly one invocation.")
        if data.get("succeeded") is not row["nativeSucceeded"]:
            reject("HISTORY_NATIVE_RESULT_CONFLICT", "native result event and success flag disagree.")
    elif event == "history.save.sidecar.begin" or (event == "history.save.end" and data.get("stage") == "sidecar_write_returned"):
        if row["kind"] != "save":
            reject("HISTORY_KIND_CONFLICT", "sidecar event belongs to no captured save callback.")
        if row["nativeEnd"] is None or row.get("nativeSucceeded") is not True:
            reject("HISTORY_SIDECAR_BEFORE_NATIVE_SUCCESS", "sidecar stage lacks a preceding successful native callback return.")
        farm_id = data.get("farmId")
        if not integer(farm_id) or farm_id < 1:
            reject("HISTORY_SIDECAR_FARM_UNAVAILABLE", "sidecar stage lacks its farm identity.")
        else:
            sidecar = row["sidecars"].setdefault(farm_id, {"begin": None, "end": None})
            phase = "begin" if event == "history.save.sidecar.begin" else "end"
            if sidecar[phase] is not None:
                reject("HISTORY_DUPLICATE_SIDECAR_STAGE", "same farm sidecar stage occurred more than once.")
            if phase == "end" and sidecar["begin"] is None:
                reject("HISTORY_SIDECAR_END_WITHOUT_BEGIN", "sidecar result lacks its matching begin.")
            sidecar[phase] = ref
    else:
        expected = "save" if event == "history.save.end" else "transaction"
        if row["kind"] != expected:
            reject("HISTORY_KIND_CONFLICT", "observer end kind differs from its begin.")
        stage = data.get("stage")
        if expected == "save" and stage not in (None, "native_callback_returned", "native_callback_error"):
            reject("HISTORY_UNKNOWN_SAVE_STAGE", "unrecognized save end stage cannot establish terminal completion.")
            return
        if row["nativeEnd"] is None:
            reject("HISTORY_END_WITHOUT_NATIVE_RESULT", "observer ended without its native result.")
        elif "succeeded" in data and data["succeeded"] is not row.get("nativeSucceeded"):
            reject("HISTORY_END_RESULT_CONFLICT", "observer and native success flags disagree.")
        if stage == "native_callback_error" and row.get("nativeSucceeded") is not False:
            reject("HISTORY_END_RESULT_CONFLICT", "save error stage lacks a native error result.")
        if stage == "native_callback_returned" and row.get("nativeSucceeded") is not True:
            reject("HISTORY_END_RESULT_CONFLICT", "save return stage lacks a native return result.")
        row["end"] = ref


def finish_history_calls(mission):
    summary = {origin: {"observedIds": 0, "completeLifecycles": 0, "incompleteLifecycles": 0} for origin in ORIGINS}
    for row in mission["_historyCalls"].values():
        counts = summary[row["origin"]]
        counts["observedIds"] += 1
        for field, code in (("begin", "HISTORY_MISSING_BEGIN"), ("nativeBegin", "HISTORY_MISSING_NATIVE_BEGIN"),
                            ("nativeEnd", "HISTORY_MISSING_NATIVE_RESULT"), ("end", "HISTORY_MISSING_END")):
            if row[field] is None:
                row["valid"] = False
                problem(mission, code, "History ID %s (%s) lacks %s in this log; this is incomplete evidence, not proof of an engine defect." %
                        (row["id"], row["origin"], field), row["first"])
        for farm_id, sidecar in row["sidecars"].items():
            if sidecar["end"] is None:
                row["valid"] = False
                problem(mission, "HISTORY_MISSING_SIDECAR_END", "Save ID %s (%s), farm %s lacks its sidecar result." %
                        (row["id"], row["origin"], farm_id), sidecar["begin"])
        counts["completeLifecycles" if row["valid"] else "incompleteLifecycles"] += 1
    mission["historyCorrelation"] = summary


def origin_of(record, data):
    # Summary.check may be written outside the synthetic execution scope. Its
    # prefixed ID remains synthetic even if the enclosing origin is runtime.
    if str(data.get("id", "")).startswith("SYNTHETIC_"):
        return "synthetic"
    return record.get("origin") if record.get("origin") in ORIGINS else "unspecified"


def check_state(mission, origin, check_id):
    key = origin + ":" + check_id
    if key not in mission["checks"]:
        mission["checks"][key] = {"id": check_id, "origin": origin, "observedCounts": Counter(),
            "summaryCounts": {}, "counts": Counter(), "references": [], "latestEvidence": None,
            "_observedAtSummary": Counter(), "_seenFailure": False}
    return mission["checks"][key]


def read_check(mission, record, data, ref, raw):
    check_id, outcome = data.get("id"), data.get("outcome")
    if not isinstance(check_id, str) or not check_id or outcome not in OUTCOMES:
        problem(mission, "INVALID_CHECK", "Check ID or outcome is invalid.", ref)
        return
    origin = origin_of(record, data)
    ref = {**ref, "origin": origin, "envelopeOrigin": ref["origin"]}
    state = check_state(mission, origin, check_id)
    state["observedCounts"][outcome] += 1
    state["counts"][outcome] += 1
    state["latestEvidence"] = data.get("evidence")
    state["references"].append({**ref, "outcome": outcome})
    mission["lastCheckLine"] = ref["line"]
    if outcome == "FAIL":
        state["_seenFailure"] = True
        mission["failureEvidence"].append({**ref, "id": check_id, "data": data, "raw": raw})
    evidence = data.get("evidence")
    if origin != "synthetic" and (check_id.startswith("MANUAL_EXPECT_") or (isinstance(evidence, dict) and
            evidence.get("oracle") == "user_supplied_native_screen_value")):
        mission["manualComparisons"].append({**ref, "id": check_id, "outcome": outcome,
            "evidence": evidence, "provenance": "User-declared observation; not independently verified."})


def read_summary_check(mission, record, data, ref, raw):
    check_id, summary = data.get("id"), data.get("state")
    if not isinstance(check_id, str) or not isinstance(summary, dict) or not isinstance(summary.get("counts"), dict):
        problem(mission, "INVALID_SUMMARY_CHECK", "Malformed cumulative check summary.", ref)
        return
    counts = summary["counts"]
    if any(key not in OUTCOMES or not integer(value) or value < 0 for key, value in counts.items()):
        problem(mission, "INVALID_SUMMARY_COUNTS", "Invalid outcome or count in summary.", ref)
        return
    origin = origin_of(record, data)
    ref = {**ref, "origin": origin, "envelopeOrigin": ref["origin"]}
    state = check_state(mission, origin, check_id)
    total = sum(counts.values())
    if summary.get("observations") != total:
        problem(mission, "SUMMARY_OBSERVATIONS_MISMATCH", check_id + " cumulative total does not match observations.", ref)
    expected = {key: state["counts"].get(key, 0) for key in OUTCOMES}
    if any(counts.get(key, 0) != expected[key] for key in OUTCOMES):
        problem(mission, "SUMMARY_EVIDENCE_MISMATCH",
                check_id + " cumulative summary differs from captured observations; missing or conflicting evidence.", ref)
    for outcome in OUTCOMES:
        # Cumulative summaries reconcile observations; they are never additional
        # observations. Max preserves previously recorded failures if a damaged
        # later summary resets a counter, and new check events add normally.
        state["counts"][outcome] = max(state["counts"].get(outcome, 0), counts.get(outcome, 0))
    state["summaryCounts"] = dict(counts)
    state["_observedAtSummary"] = dict(state["observedCounts"])
    state["summaryReference"] = ref
    if counts.get("FAIL", 0):
        state["_seenFailure"] = True
        # Summary-only failures have no original failed check line available.
        if counts["FAIL"] > state["observedCounts"].get("FAIL", 0):
            mission["failureEvidence"].append({**ref, "id": check_id, "data": data, "raw": raw,
                                               "summaryOnly": True})


def read_event(mission, record, ref, raw):
    event, data = record["event"], record.get("data")
    if not isinstance(data, dict):
        problem(mission, "INVALID_DATA", "Event data must be an object.", ref)
        return
    origin = origin_of(record, data)
    mission["eventCounts"][origin][event] += 1
    if not event.startswith("summary.") and event != "mission.end":
        mission["lastActivityLine"] = ref["line"]
    if record.get("evidenceTruncated") is True:
        problem(mission, "EVIDENCE_TRUNCATED", "Logger truncated this record.", ref)
    if event == "mission.begin":
        if mission["began"]:
            problem(mission, "DUPLICATE_MISSION_BEGIN", "Repeated mission begin without a new identity.", ref)
        mission["began"], mission["metadata"] = True, data
    elif event == "mission.end":
        mission["ended"] = True
        mission["missionEndLine"] = ref["line"]
    elif event == "debug.off":
        problem(mission, "DEBUG_DISABLED", "Logging was disabled; activity outside the captured interval is unknown.", ref)
    elif event == "log.limit":
        problem(mission, "LOG_BUDGET_LIMIT", "Logger event/byte budget exhausted; evidence was dropped.", ref)
    elif event == "capture.begin":
        key = (origin, record["capture"])
        if key in mission["_openCaptures"]:
            problem(mission, "CAPTURE_RESTARTED", "Capture began again before its end.", ref)
        capture = {"id": record["capture"], "origin": origin, "begin": ref, "reason": data.get("reason"), "complete": False}
        mission["captures"].append(capture)
        mission["_openCaptures"][key] = capture
    elif event == "capture.end":
        capture = mission["_openCaptures"].pop((origin, record["capture"]), None)
        if capture is None:
            problem(mission, "CAPTURE_END_WITHOUT_BEGIN", "Capture end has no captured begin.", ref)
        else:
            capture.update(end=ref, complete=True, result=data)
        if data.get("ok") is False:
            mission["failureEvidence"].append({**ref, "data": data, "raw": raw})
    elif event == "dump.begin":
        key = (origin, record["capture"], str(data.get("name")))
        if key in mission["_openDumps"]:
            problem(mission, "DUMP_RESTARTED", "Dump began before the earlier dump finished.", ref)
        dump = {"name": data.get("name"), "capture": record["capture"], "origin": origin, "begin": ref, "complete": False}
        mission["dumps"].append(dump)
        mission["_openDumps"][key] = dump
    elif event == "dump.end":
        dump = mission["_openDumps"].pop((origin, record["capture"], str(data.get("name"))), None)
        if dump is None:
            problem(mission, "DUMP_END_WITHOUT_BEGIN", "Dump end has no captured begin.", ref)
        else:
            dump.update(end=ref, complete=data.get("complete") is True)
        if data.get("complete") is not True:
            problem(mission, "DUMP_INCOMPLETE", "Dump reports incomplete serialization.", ref)
    elif event in ("dump.incomplete", "dump.omitted"):
        problem(mission, "DUMP_INCOMPLETE", "Dump data was omitted or incomplete.", ref)
    elif event == "dump.value" and origin == "runtime":
        path = data.get("path", "")
        if isinstance(path, str) and CAPABILITY_PATH.match(path):
            mission["latestCapabilities"][path] = {"value": data.get("value"), **ref}
        if isinstance(path, str) and GATE_PATH.match(path) and any(
                word in path for word in ("verification", "windowStatus", "materialGaps", "withheld", "status", "completePeriodCount", "requiredPeriodCount")):
            mission["latestGates"][path] = {"value": data.get("value"), **ref}
    elif event in ("underwriting.gate", "underwriting.forecast") and origin == "runtime":
        mission["latestGates"][event] = {"data": data, **ref}
    elif event == "check":
        read_check(mission, record, data, ref, raw)
    elif event == "summary.begin":
        if mission["_summary"] is not None:
            problem(mission, "SUMMARY_RESTARTED", "Previous summary never ended.", ref)
        mission["_summary"] = ref
        failure_ids = data.get("failureIds", {})
        if not isinstance(failure_ids, dict):
            problem(mission, "INVALID_FAILURE_SUMMARY", "Bounded failure summary is malformed.", ref)
        else:
            for check_id, counts in failure_ids.items():
                count = counts.get("FAIL") if isinstance(counts, dict) else None
                if not isinstance(check_id, str) or not integer(count) or count < 1:
                    problem(mission, "INVALID_FAILURE_SUMMARY", "Bounded failure ID/count is malformed.", ref)
                    continue
                check_origin = origin_of(record, {"id": check_id})
                failure_ref = {**ref, "origin": check_origin, "envelopeOrigin": ref["origin"]}
                state = check_state(mission, check_origin, check_id)
                if count > state["counts"].get("FAIL", 0):
                    problem(mission, "SUMMARY_FAILURE_WITHOUT_EVENT", check_id + " has failed checks absent from captured events.", ref)
                    mission["failureEvidence"].append({**failure_ref, "id": check_id, "data": data, "raw": raw, "summaryOnly": True})
                state["counts"]["FAIL"] = max(count, state["counts"].get("FAIL", 0))
                state["_seenFailure"] = True
                state["summaryReference"] = failure_ref
        if data.get("failureListTruncated") is True:
            problem(mission, "FAILURE_LIST_TRUNCATED", "Additional failed check IDs could not be included in the bounded summary.", ref)
        if "totalFailedChecks" in data:
            mission["reportedFailedCheckIds"] = data["totalFailedChecks"]
            total = data["totalFailedChecks"]
            if not integer(total) or total < 0 or (isinstance(failure_ids, dict) and
                    (total < len(failure_ids) or (total > len(failure_ids) and data.get("failureListTruncated") is not True))):
                problem(mission, "INVALID_FAILURE_SUMMARY", "Reported failed-check total does not reconcile with the bounded ID list.", ref)
    elif event == "summary.check":
        read_summary_check(mission, record, data, ref, raw)
    elif event == "summary.coverage":
        check_id = data.get("id")
        if isinstance(check_id, str):
            mission["summaryCoverage"][check_id] = data
            if data.get("outcome") != "NOT_EXERCISED":
                problem(mission, "UNSUPPORTED_SCENARIO_RESULT", "A summary coverage row cannot certify its whole scenario.", ref)
        else:
            problem(mission, "INVALID_COVERAGE", "Coverage entry lacks a scenario ID.", ref)
    elif event == "summary.end":
        if mission["_summary"] is None:
            problem(mission, "SUMMARY_END_WITHOUT_BEGIN", "Summary end has no captured begin.", ref)
        mission["_summary"] = None
        mission["summaries"] += 1
        mission["lastSummaryLine"] = ref["line"]
        if data.get("evidenceComplete") is not True:
            problem(mission, "SUMMARY_INCOMPLETE", "Logger does not declare its evidence transport complete.", ref)
    if event in ("summary.begin", "summary.end"):
        for field in ("dropped", "truncated", "loggerErrors"):
            value = data.get(field, 0)
            if not integer(value) or value != 0:
                problem(mission, "LOGGER_" + field.upper(), field + "=" + str(value), ref)
    if event == "history.transaction.begin" and integer(data.get("transactionId")):
        mission["_transactionIds"][origin].add(data["transactionId"])
    if event == "history.save.begin" and integer(data.get("transactionId")):
        mission["_saveIds"][origin].add(data["transactionId"])
    read_history_call(mission, event, data, origin, ref)
    # Old validation builds use succeeded=false for an absent first-use sidecar
    # and absent XML capability. Keep these visible, without treating absence as
    # a failed read attempt. Malformed/read-failed files remain failure evidence.
    availability_only = event == "history.xml.read" and data.get("succeeded") is False and data.get("reason") in (
        "Sidecar absent", "Native XML functions unavailable")
    if availability_only:
        mission["availabilityEvidence"].append({**ref, "data": data, "raw": raw, "outcome": "UNAVAILABLE"})
    if event.endswith(".error") or event.endswith(".recordError") or (data.get("succeeded") is False and not availability_only) or data.get("written") is False or data.get("nativeReturnedFalse") is True:
        mission["failureEvidence"].append({**ref, "data": data, "raw": raw})


def finish_mission(mission, catalog):
    finish_history_calls(mission)
    pre_mission = mission["mission"] == 0
    mission["context"] = "pre-mission diagnostics" if pre_mission else "mission"
    if not mission["began"] and not pre_mission:
        problem(mission, "MISSING_MISSION_BEGIN", "No mission.begin; logging may have started late.")
    if not mission["ended"] and not pre_mission:
        problem(mission, "MISSING_MISSION_END", "No mission.end; the session may still be active. This is incomplete evidence, not proof of a crash.")
    for capture in mission["_openCaptures"].values():
        problem(mission, "MISSING_CAPTURE_END", "Capture never ended in this log.", capture["begin"])
    for dump in mission["_openDumps"].values():
        problem(mission, "MISSING_DUMP_END", "Snapshot dump never ended in this log.", dump["begin"])
    if mission["_summary"] is not None:
        problem(mission, "MISSING_SUMMARY_END", "Cumulative summary was cut short.", mission["_summary"])
    if not mission["summaries"] and not pre_mission:
        problem(mission, "MISSING_SUMMARY", "No complete cumulative summary or runtime coverage inventory.")
    elif mission["lastSummaryLine"] and max(mission["lastActivityLine"] or 0, mission.get("missionEndLine", 0)) > mission["lastSummaryLine"]:
        problem(mission, "STALE_SUMMARY", "Evidence activity or mission end followed the last summary; final reconciliation is missing.")
    if not pre_mission and not any(row["origin"] == "runtime" and row["complete"] and row.get("result", {}).get("ok") is True for row in mission["captures"]):
        problem(mission, "NO_COMPLETE_RUNTIME_CAPTURE", "No completed runtime snapshot capture was recorded.")
    for capture in mission["captures"]:
        if capture.get("result", {}).get("ok") is False:
            problem(mission, "CAPTURE_FAILED", "Capture ended with an error; no successful snapshot can be inferred.", capture.get("end"))
        if capture.get("result", {}).get("ok") is True and not any(dump["name"] == "snapshot" and dump["capture"] == capture["id"] and dump["origin"] == capture["origin"] and dump["complete"] for dump in mission["dumps"]):
            problem(mission, "MISSING_SNAPSHOT_DUMP", "Successful capture lacks its completed snapshot dump.", capture["begin"])
    for state in mission["checks"].values():
        counts = state["counts"]
        state["status"] = next((outcome for outcome in ("FAIL", "WARN", "UNAVAILABLE", "NOT_EXERCISED", "PASS") if counts.get(outcome, 0)), "NOT_EXERCISED")
        if state["_seenFailure"]:
            state["status"] = "FAIL"
        for key in list(state):
            if key.startswith("_"):
                del state[key]
    scenarios = {row["id"]: {**row, "status": "NOT_EXERCISED"} for row in catalog.get("checks", [])}
    for check_id, row in mission["summaryCoverage"].items():
        scenarios.setdefault(check_id, {**row, "status": "NOT_EXERCISED"})
    mission["scenarioCoverage"] = list(sorted(scenarios.values(), key=lambda row: row["id"]))
    mission["scenarioCoverageStatus"] = "NOT_EXERCISED" if scenarios else "UNAVAILABLE"
    if not scenarios:
        problem(mission, "CATALOG_NOT_SUPPLIED", "No local catalog or runtime scenario inventory was supplied.")
    mission["activity"] = {}
    for origin in ORIGINS:
        events = mission["eventCounts"][origin]
        mission["activity"][origin] = {
            "transactionIds": len(mission["_transactionIds"][origin]),
            "saveIds": len(mission["_saveIds"][origin]),
            "transactionEndEvents": events["history.transaction.end"],
            "saveEndEvents": events["history.save.end"],
            "periodCloseEvents": events["history.period.close"], "resumeEvents": events["history.resume"]}
    mission["outcomeCounts"] = {origin: {outcome: sum(state["counts"].get(outcome, 0)
        for state in mission["checks"].values() if state["origin"] == origin) for outcome in OUTCOMES} for origin in ORIGINS}
    mission["integrity"] = "INCOMPLETE" if mission["problems"] else "CAPTURED"
    mission["validation"] = "FAILURES_RECORDED" if mission["failureEvidence"] else "LIMITED_EVIDENCE"
    for key in list(mission):
        if key.startswith("_"):
            del mission[key]


def analyze_lines(lines, source="<memory>", catalog=None):
    catalog = catalog or {"source": None, "status": "unavailable", "checks": []}
    report = {"schema": 1, "source": source, "status": "INCOMPLETE", "problems": [],
              "catalog": catalog, "runs": [], "nativeWarnings": [], "malformedLines": [], "validationLines": 0,
              "scope": "Captured implementation evidence only; not proof of native-screen accuracy, scenario completion, or real-world underwriting accuracy."}
    run, mission, previous_seq, previous_raw = None, None, None, None
    line_number = 0
    for line_number, line in enumerate(lines, 1):
        raw = line.rstrip("\r\n")
        if PREFIX not in raw:
            if NATIVE_WARNING.search(raw):
                report["nativeWarnings"].append({"line": line_number, "raw": raw, "attribution": "Not automatically attributed to Lizard Bank."})
            continue
        report["validationLines"] += 1
        payload = raw.split(PREFIX, 1)[1].strip()
        try:
            record = json.loads(payload, parse_constant=reject_constant, object_pairs_hook=unique_object)
            if not isinstance(record, dict):
                raise ValueError("Envelope is not an object")
        except (ValueError, RecursionError) as error:
            row = {"line": line_number, "error": str(error), "raw": raw}
            report["malformedLines"].append(row)
            problem(mission or report, "MALFORMED_JSON", "Invalid or truncated validation JSON.", {"line": line_number})
            continue
        ref = reference(line_number, record)
        if not integer(record.get("seq")) or record["seq"] < 1 or not integer(record.get("mission")) or record["mission"] < 0 or not integer(record.get("capture")) or record["capture"] < 0 or not isinstance(record.get("event"), str):
            problem(mission or report, "INVALID_ENVELOPE", "Invalid sequence, mission, capture, or event.", ref)
            report["malformedLines"].append({**ref, "raw": raw, "error": "Invalid envelope"})
            continue
        seq = record["seq"]
        if run is None or (previous_seq is not None and seq < previous_seq):
            run = {"id": len(report["runs"]) + 1, "startLine": line_number, "missions": []}
            report["runs"].append(run)
            previous_seq, previous_raw = None, None
            if seq != 1:
                problem(report, "RUN_START_SEQUENCE", "Process run starts after sequence 1; beginning evidence is missing.", ref)
        candidates = [item for item in run["missions"] if item["mission"] == record["mission"]]
        mission = candidates[0] if candidates else new_mission(run["id"], record["mission"])
        if not candidates:
            run["missions"].append(mission)
        if previous_seq is not None:
            if seq == previous_seq:
                problem(mission, "DUPLICATE_SEQUENCE", "Repeated sequence; exact duplicate is not counted twice, conflicting evidence is retained.", ref)
                if payload == previous_raw:
                    continue
            elif seq != previous_seq + 1:
                problem(mission, "SEQUENCE_GAP", "Missing sequences %d..%d; dropped evidence or a partial log." % (previous_seq + 1, seq - 1), ref)
        previous_seq, previous_raw = seq, payload
        if record.get("schema") != 1 or isinstance(record.get("schema"), bool):
            problem(mission, "UNKNOWN_SCHEMA", "Unsupported schema; this record's claims are not interpreted.", ref)
            continue
        if record.get("origin") not in ("runtime", "synthetic"):
            problem(mission, "ORIGIN_UNSPECIFIED", "Native versus synthetic provenance is unavailable; no native activity inferred.", ref)
        read_event(mission, record, ref, raw)
    report["lineCount"] = line_number
    if not report["validationLines"]:
        problem(report, "NO_VALIDATION_EVENTS", "No structured validation evidence. Diagnostics may be off or this may be an older log; no all-clear can be inferred.")
    if catalog.get("status") != "available":
        problem(report, "CATALOG_UNAVAILABLE", "Local catalog is unavailable/partial; coverage may be incomplete even if runtime rows exist.")
    for run in report["runs"]:
        for mission in run["missions"]:
            finish_mission(mission, catalog)
    if not any(m["mission"] > 0 for r in report["runs"] for m in r["missions"]):
        problem(report, "NO_RUNTIME_MISSION", "No mission evidence was captured; startup or debug-mode messages alone exercise no mission scenario.")
    report["integrity"] = "INCOMPLETE" if report["problems"] or any(m["problems"] for r in report["runs"] for m in r["missions"]) else "CAPTURED"
    report["failureCount"] = sum(len(m["failureEvidence"]) for r in report["runs"] for m in r["missions"])
    # Scenario truth is external to this transport. Even a complete, clean log
    # establishes only limited internal evidence, never an all-clear milestone.
    report["coverage"] = "NOT_EXERCISED" if catalog.get("checks") else "UNAVAILABLE"
    return report


def inline(value):
    text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False, sort_keys=True)
    return text.replace("\n", " ").replace("\r", " ").replace("|", "\\|").replace("`", "'")


def where(row):
    return "line %s, seq %s, capture %s" % (row.get("line", "?"), row.get("seq", "?"), row.get("capture", "?"))


def render_markdown(report):
    out = ["# Lizard Bank validation evidence", "", "**INCOMPLETE validation coverage.** Transport integrity: **%s**. Failure evidence records: **%s**." % (report["integrity"], report["failureCount"]), "",
        "Source: `%s` (%s physical lines; %s validation records)." % (inline(report["source"]), report["lineCount"], report["validationLines"]), "", report["scope"], "",
        "Runtime, synthetic fixtures, and user-declared comparisons are separate. Synthetic passes do not exercise native callbacks, saves, asset ownership, or twelve in-game periods. A runtime PASS only establishes its named check; catalog scenarios remain NOT_EXERCISED without independent review.", ""]
    if report["problems"]:
        out += ["## Log integrity", ""]
        out += ["- **%s**: %s (%s)." % (p["code"], inline(p["message"]), where(p)) for p in report["problems"]]
        out.append("")
    for run in report["runs"]:
        for mission in run["missions"]:
            out += ["## Process run %s · %s %s" % (run["id"], mission["context"], mission["mission"]), "",
                "Integrity: **%s**. Result scope: **%s**. Captures: %s; completed: %s. Summaries: %s." % (mission["integrity"], mission["validation"], len(mission["captures"]), sum(c["complete"] for c in mission["captures"]), mission["summaries"]), ""]
            if "reportedFailedCheckIds" in mission:
                out += ["Latest bounded summary reports **%s failed check IDs** across runtime and synthetic evidence; any truncated ID list remains incomplete." % inline(mission["reportedFailedCheckIds"]), ""]
            for p in mission["problems"]:
                out.append("- **%s**: %s (%s)." % (p["code"], inline(p["message"]), where(p)))
            out += ["", "| Evidence origin | PASS | FAIL | WARN | UNAVAILABLE | NOT_EXERCISED |", "| --- | ---: | ---: | ---: | ---: | ---: |"]
            for origin in ORIGINS:
                out.append("| %s | %s |" % (origin, " | ".join(str(mission["outcomeCounts"][origin][key]) for key in OUTCOMES)))
            out += ["", "Counts are cumulative check observations, reconciled with summaries without adding duplicate summary counts. FAIL remains recorded after later PASS.", "",
                "| Origin | Transaction IDs | Save IDs | Transaction end events | Save end events | Period-close events | Resume events |", "| --- | ---: | ---: | ---: | ---: | ---: | ---: |"]
            for origin, activity in mission["activity"].items():
                out.append("| %s | %s |" % (origin, " | ".join(str(value) for value in activity.values())))
            out += ["", "These are observed events, not completed test scenarios. Save-end stages may occur more than once per save; a logged period close alone does not prove twelve complete, reconciled seasonal periods.", "",
                        "### History call correlation", "", "Each complete lifecycle pairs one observer begin, one native invocation/result and its terminal end. Sidecar stages are matched per farm; nested calls have separate IDs. This is transport evidence, not proof of whole native save completion.", "",
                        "| Origin | Observed IDs | Complete lifecycles | Incomplete lifecycles |", "| --- | ---: | ---: | ---: |"]
            for origin, counts in mission["historyCorrelation"].items():
                out.append("| %s | %s |" % (origin, " | ".join(str(value) for value in counts.values())))
            out += ["", "### Captures", ""]
            for capture in mission["captures"]:
                out.append("- Capture %s (%s), %s: %s; %s." % (capture["id"], capture["origin"], inline(capture.get("reason")), "end recorded" if capture["complete"] else "INCOMPLETE", where(capture["begin"])))
            if not mission["captures"]:
                out.append("No capture evidence.")
            out += ["", "### Check results", "", "| Origin / check | Sticky result | Counts | Latest evidence reference |", "| --- | --- | --- | --- |"]
            for state in sorted(mission["checks"].values(), key=lambda row: (row["origin"], row["id"])):
                ref = state["references"][-1] if state["references"] else state.get("summaryReference", {})
                out.append("| %s / %s | %s | %s | %s |" % (state["origin"], inline(state["id"]), state["status"], inline(dict(state["counts"])), where(ref)))
            out += ["", "### User-declared comparisons", "", "These entries compare supplied numbers. The analyzer cannot verify what the user read, which screen was open, or whether that observation was current.", ""]
            out += ["- %s: %s; %s; %s." % (inline(row["id"]), row["outcome"], inline(row["evidence"]), where(row)) for row in mission["manualComparisons"]] or ["None recorded."]
            out += ["", "### Latest captured capabilities and financial gates", "", "Retained native finance layout/window and any twelve-period model gate require independent native validation. A model becoming available is not evidence of forecast or underwriting accuracy.", ""]
            for heading, rows in (("Capabilities", mission["latestCapabilities"]), ("Financial / model evidence", mission["latestGates"])):
                out.append("**%s**" % heading)
                out.append("")
                out += ["- `%s`: %s (%s)." % (inline(path), inline(row.get("data", row.get("value"))), where(row)) for path, row in sorted(rows.items())] or ["Not captured; unavailable."]
                out.append("")
            out += ["### Scenario coverage", "", "All %s listed scenarios remain **NOT_EXERCISED** by this analyzer. Low-level invariants and synthetic fixture success do not certify these scenarios. Local catalog: `%s` (%s)." % (len(mission["scenarioCoverage"]), inline(report["catalog"].get("source")), report["catalog"].get("status")), ""]
            out += ["- **%s** [%s]: %s — NOT_EXERCISED." % (row["id"], row.get("evidence", "unknown"), inline(row.get("description", "Description unavailable"))) for row in mission["scenarioCoverage"]]
            out += ["", "### Unavailable history sources", "",
                    "Absence can be normal on first use; these records neither establish a read failure nor prove saved history should have been absent.", ""]
            out += ["- **UNAVAILABLE**: %s (%s)." % (inline(row["data"]), where(row)) for row in mission["availabilityEvidence"]] or ["None recorded."]
            out += ["", "### Failure evidence", ""]
            if not mission["failureEvidence"]:
                out.append("No failure record captured. This does not establish that unobserved behavior passed.")
            for row in mission["failureEvidence"]:
                out += ["- **%s** (%s, %s):" % (inline(row.get("id", row.get("event"))), row.get("origin"), where(row)), "", "    " + row["raw"], ""]
            out.append("")
    if report["malformedLines"]:
        out += ["## Unparsed validation lines", ""]
        for row in report["malformedLines"]:
            out += ["- Line %s: %s" % (row["line"], inline(row["error"])), "", "    " + row["raw"], ""]
    out += ["## Other game log warnings and errors", "", "Preserved verbatim for review; attribution to Lizard Bank is not assumed.", ""]
    for row in report["nativeWarnings"]:
        out += ["- Line %s:" % row["line"], "", "    " + row["raw"], ""]
    if not report["nativeWarnings"]:
        out.append("No matching warning/error lines found. This is not a native log validation result.")
    return "\n".join(out).rstrip() + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path, help="Original FS25 log.txt or a saved copy")
    parser.add_argument("--output", type=Path, help="Write Markdown here instead of stdout")
    parser.add_argument("--json", dest="json_output", type=Path, help="Also write structured JSON here")
    parser.add_argument("--catalog", type=Path, default=CATALOG_PATH, help="Declarative local validation catalog")
    args = parser.parse_args(argv)
    # Never overwrite original evidence, even through a relative path/symlink.
    paths = [path.resolve() for path in (args.log, args.output, args.json_output) if path is not None]
    if len(paths) != len(set(paths)):
        parser.error("Input, Markdown output, and JSON output must be different files.")
    try:
        with args.log.open("r", encoding="utf-8-sig", errors="replace") as handle:
            report = analyze_lines(handle, str(args.log), load_catalog(args.catalog))
        markdown = render_markdown(report)
        if args.output:
            args.output.write_text(markdown, encoding="utf-8")
        else:
            sys.stdout.write(markdown)
        if args.json_output:
            args.json_output.write_text(json.dumps(report, indent=2, ensure_ascii=False, allow_nan=False) + "\n", encoding="utf-8")
    except OSError as error:
        parser.exit(2, "analyze_log.py: %s\n" % error)
    # Successful analysis is not a validation PASS; status is in the report.
    return 0


if __name__ == "__main__":
    sys.exit(main())
