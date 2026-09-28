"""Offline evidence parser fixtures. These are not Windows gameplay tests."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("analyze_log", ROOT / "tools" / "analyze_log.py")
analyzer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(analyzer)
CATALOG = {"source": "fixture catalog", "status": "available", "checks": [
    {"id": "LIFE-001", "group": "LIFE", "evidence": "manual", "description": "Native lifecycle scenario"},
    {"id": "FIN-001", "group": "FIN", "evidence": "runtime", "description": "Finance window reconciliation"}]}


class Log:
    def __init__(self, mission=1):
        self.lines, self.seq, self.mission, self.capture = [], 0, mission, 0

    def add(self, event, data=None, origin="runtime", **overrides):
        self.seq += 1
        record = {"schema": 1, "seq": self.seq, "mission": self.mission,
                  "capture": self.capture, "event": event, "data": data or {}, "origin": origin}
        record.update(overrides)
        self.lines.append("2026-09-27 12:00:00 " + analyzer.PREFIX + " " + json.dumps(record))
        return self

    def begin(self):
        return self.add("mission.begin", {"meta": {"gameVersion": "fixture", "farmId": 7}})

    def snapshot(self):
        self.capture += 1
        self.add("capture.begin", {"reason": "fixture"})
        self.add("dump.begin", {"name": "snapshot"})
        self.add("dump.container", {"path": "snapshot"})
        self.add("dump.end", {"name": "snapshot", "complete": True})
        return self.add("capture.end", {"ok": True, "farmId": 7})

    def check(self, check_id, outcome, evidence=None, origin="runtime"):
        return self.add("check", {"id": check_id, "outcome": outcome, "evidence": evidence or {}}, origin)

    def summary(self, states=None, **metadata):
        self.add("summary.begin", {"reason": "fixture", "dropped": 0, "truncated": 0, "loggerErrors": 0, **metadata})
        for check_id, counts in (states or {}).items():
            self.add("summary.check", {"id": check_id, "state": {"observations": sum(counts.values()), "counts": counts}})
        for row in CATALOG["checks"]:
            self.add("summary.coverage", {**row, "outcome": "NOT_EXERCISED"})
        return self.add("summary.end", {"evidenceComplete": True, "dropped": 0, "loggerErrors": 0})

    def finish(self, states=None):
        return self.add("mission.end").summary(states)

    def report(self, catalog=CATALOG):
        return analyzer.analyze_lines(self.lines, "fixture log", catalog)


def mission(report, run=0, index=0):
    return report["runs"][run]["missions"][index]


def codes(report):
    result = {p["code"] for p in report["problems"]}
    result.update(p["code"] for run in report["runs"] for m in run["missions"] for p in m["problems"])
    return result


class AnalyzerTests(unittest.TestCase):
    def test_clean_transport_never_claims_scenario_or_real_world_success(self):
        report = Log().begin().snapshot().check("AUTO_CASH_FINITE", "PASS").finish({"AUTO_CASH_FINITE": {"PASS": 1}}).report()
        self.assertEqual(report["integrity"], "CAPTURED")
        self.assertEqual(report["status"], "INCOMPLETE")
        self.assertEqual(mission(report)["scenarioCoverageStatus"], "NOT_EXERCISED")
        self.assertTrue(all(row["status"] == "NOT_EXERCISED" for row in mission(report)["scenarioCoverage"]))
        markdown = analyzer.render_markdown(report)
        self.assertIn("not proof", markdown)
        self.assertIn("INCOMPLETE validation coverage", markdown)

    def test_sticky_fail_then_pass_and_repeated_summaries_not_added(self):
        log = Log().begin().snapshot().check("CHECK", "FAIL", {"value": 2}).check("CHECK", "PASS", {"value": 1})
        log.summary({"CHECK": {"FAIL": 1, "PASS": 1}}).summary({"CHECK": {"FAIL": 1, "PASS": 1}})
        report = log.finish({"CHECK": {"FAIL": 1, "PASS": 1}}).report()
        state = mission(report)["checks"]["runtime:CHECK"]
        self.assertEqual(state["status"], "FAIL")
        self.assertEqual(state["counts"]["FAIL"], 1)
        self.assertEqual(state["counts"]["PASS"], 1)
        self.assertEqual(len(mission(report)["failureEvidence"]), 1)
        self.assertIn('"outcome": "FAIL"', analyzer.render_markdown(report))

    def test_lost_check_recovered_from_summary_without_double_counting_later_event(self):
        log = Log().begin().snapshot().check("CHECK", "PASS")
        log.summary({"CHECK": {"PASS": 2, "FAIL": 1}}).check("CHECK", "PASS")
        report = log.finish({"CHECK": {"PASS": 3, "FAIL": 1}}).report()
        state = mission(report)["checks"]["runtime:CHECK"]
        self.assertEqual(state["counts"]["PASS"], 3)
        self.assertEqual(state["counts"]["FAIL"], 1)
        self.assertIn("SUMMARY_EVIDENCE_MISMATCH", codes(report))
        self.assertTrue(mission(report)["failureEvidence"][0]["summaryOnly"])

    def test_regressing_summary_cannot_erase_failure(self):
        log = Log().begin().snapshot().check("CHECK", "FAIL")
        report = log.finish({"CHECK": {"PASS": 1}}).report()
        state = mission(report)["checks"]["runtime:CHECK"]
        self.assertEqual(state["status"], "FAIL")
        self.assertEqual(state["counts"]["FAIL"], 1)
        self.assertIn("SUMMARY_EVIDENCE_MISMATCH", codes(report))

    def test_distinct_warning_unknown_and_not_exercised_counts(self):
        log = Log().begin().snapshot()
        states = {}
        for index, outcome in enumerate(analyzer.OUTCOMES):
            log.check("C" + str(index), outcome)
            states["C" + str(index)] = {outcome: 1}
        report = log.finish(states).report()
        self.assertEqual(mission(report)["outcomeCounts"]["runtime"], dict.fromkeys(analyzer.OUTCOMES, 1))

    def test_timestamp_prefix_and_lua_numeric_object_keys_preserved(self):
        log = Log().begin().snapshot()
        log.add("underwriting.gate", {"status": "withheld", "withheldReasonCodes": {"1": "HISTORY_INCOMPLETE", "2": "FARM_UNKNOWN"}})
        report = log.finish().report()
        reasons = mission(report)["latestGates"]["underwriting.gate"]["data"]["withheldReasonCodes"]
        self.assertEqual(reasons["2"], "FARM_UNKNOWN")

    def test_malformed_truncated_json_and_native_warnings_preserved(self):
        log = Log().begin()
        log.lines.extend(['2026 [LizardBank:VALIDATION] {"schema":1,', "2026 Warning: third-party asset missing", "Error: LUA call stack:"])
        report = log.report()
        self.assertIn("MALFORMED_JSON", codes(report))
        self.assertEqual(len(report["nativeWarnings"]), 2)
        markdown = analyzer.render_markdown(report)
        self.assertIn("third-party asset missing", markdown)
        self.assertIn("not assumed", markdown)
        self.assertIn(log.lines[1], markdown)

    def test_nonfinite_json_invalid_envelopes_and_unknown_schema_not_trusted(self):
        log = Log().begin()
        log.lines.append(analyzer.PREFIX + ' {"schema":1,"seq":NaN}')
        log.add("check", {"id": "BAD", "outcome": "PASS"}, schema=99)
        log.add("check", {"id": "BAD2", "outcome": "PASS"}, seq=True)
        report = log.report()
        self.assertTrue({"MALFORMED_JSON", "INVALID_ENVELOPE", "UNKNOWN_SCHEMA"}.issubset(codes(report)))
        self.assertFalse(mission(report)["checks"])

    def test_budget_gaps_truncation_logger_error_never_all_clear(self):
        log = Log().begin().snapshot()
        log.seq += 3
        log.add("log.limit", {"dropped": 3})
        log.add("read", {"accessor": "fixture"}, evidenceTruncated=True)
        report = log.add("mission.end").summary(dropped=3, truncated=1, loggerErrors=1).report()
        self.assertTrue({"SEQUENCE_GAP", "LOG_BUDGET_LIMIT", "EVIDENCE_TRUNCATED", "LOGGER_DROPPED", "LOGGER_TRUNCATED", "LOGGER_LOGGERERRORS"}.issubset(codes(report)))
        self.assertEqual(report["integrity"], "INCOMPLETE")

    def test_missing_capture_dump_summary_and_mission_ends(self):
        log = Log().begin().add("capture.begin", {"reason": "fixture"})
        log.add("dump.begin", {"name": "snapshot"}).add("summary.begin")
        report = log.report()
        self.assertTrue({"MISSING_CAPTURE_END", "MISSING_DUMP_END", "MISSING_SUMMARY_END", "MISSING_SUMMARY", "MISSING_MISSION_END"}.issubset(codes(report)))
        self.assertIn("not proof of a crash", analyzer.render_markdown(report))

    def test_dump_incomplete_false_omitted_and_end_without_begin(self):
        log = Log().begin().snapshot()
        log.add("dump.end", {"name": "missing", "complete": False})
        log.add("dump.omitted", {"path": 'snapshot["cyclic"]', "reason": "cycle"})
        report = log.finish().report()
        self.assertTrue({"DUMP_END_WITHOUT_BEGIN", "DUMP_INCOMPLETE"}.issubset(codes(report)))

    def test_seq_reset_groups_processes_and_mission_change_groups_same_process(self):
        first = Log().begin().snapshot().finish()
        first.mission = 2
        first.begin().snapshot().finish()
        second = Log().begin().snapshot().finish()
        report = analyzer.analyze_lines(first.lines + second.lines, catalog=CATALOG)
        self.assertEqual(len(report["runs"]), 2)
        self.assertEqual([m["mission"] for m in report["runs"][0]["missions"]], [1, 2])
        self.assertEqual(len(report["runs"][1]["missions"]), 1)

    def test_duplicate_sequence_exact_copy_not_counted_but_conflicting_fail_retained(self):
        log = Log().begin().snapshot().check("C", "PASS")
        log.lines.append(log.lines[-1])
        log.add("check", {"id": "C", "outcome": "FAIL"}, seq=log.seq)
        report = log.finish({"C": {"PASS": 1, "FAIL": 1}}).report()
        state = mission(report)["checks"]["runtime:C"]
        self.assertEqual(state["counts"]["PASS"], 1)
        self.assertEqual(state["status"], "FAIL")
        self.assertIn("DUPLICATE_SEQUENCE", codes(report))

    def test_no_activity_or_diagnostics_off_is_incomplete(self):
        report = analyzer.analyze_lines(["Lizard Bank ready.", "Ordinary game activity."], catalog=CATALOG)
        self.assertIn("NO_VALIDATION_EVENTS", codes(report))
        self.assertEqual(report["status"], "INCOMPLETE")
        log = Log().begin().snapshot().add("debug.off").finish()
        self.assertIn("DEBUG_DISABLED", codes(log.report()))

    def test_partial_start_and_late_check_without_final_summary(self):
        log = Log()
        log.seq = 7
        log.snapshot().summary().check("LATE", "PASS").add("mission.end")
        report = log.report()
        self.assertTrue({"RUN_START_SEQUENCE", "MISSING_MISSION_BEGIN", "STALE_SUMMARY"}.issubset(codes(report)))

    def test_user_values_stay_user_declared_and_do_not_pass_scenario(self):
        evidence = {"expected": 100, "actual": 100, "oracle": "user_supplied_native_screen_value"}
        log = Log().begin().snapshot().check("MANUAL_EXPECT_cash", "PASS", evidence)
        report = log.finish({"MANUAL_EXPECT_cash": {"PASS": 1}}).report()
        comparison = mission(report)["manualComparisons"][0]
        self.assertEqual(comparison["evidence"], evidence)
        self.assertIn("not independently verified", comparison["provenance"])
        self.assertEqual(mission(report)["scenarioCoverageStatus"], "NOT_EXERCISED")
        self.assertIn("cannot verify what the user read", analyzer.render_markdown(report))

    def test_synthetic_transactions_periods_and_gates_never_native_evidence(self):
        log = Log().begin().snapshot()
        log.add("history.transaction.begin", {"transactionId": 1}, "synthetic")
        log.add("history.save.begin", {"transactionId": 2}, "synthetic")
        for _ in range(12):
            log.add("history.period.close", {"complete": True}, "synthetic")
        log.add("underwriting.gate", {"status": "available", "score": 99}, "synthetic")
        log.check("SYNTHETIC_MODEL", "PASS", origin="synthetic")
        report = log.finish({"SYNTHETIC_MODEL": {"PASS": 1}}).report()
        m = mission(report)
        self.assertEqual(m["activity"]["runtime"]["periodCloseEvents"], 0)
        self.assertEqual(m["activity"]["synthetic"]["periodCloseEvents"], 12)
        self.assertEqual(m["outcomeCounts"]["runtime"]["PASS"], 0)
        self.assertEqual(m["outcomeCounts"]["synthetic"]["PASS"], 1)
        self.assertFalse(m["latestGates"])

    def test_missing_origin_not_promoted_to_runtime(self):
        log = Log().begin().snapshot()
        record = {"schema": 1, "seq": log.seq + 1, "mission": 1, "capture": 1, "event": "history.period.close", "data": {}}
        log.lines.append(analyzer.PREFIX + " " + json.dumps(record))
        report = log.report()
        self.assertIn("ORIGIN_UNSPECIFIED", codes(report))
        self.assertEqual(mission(report)["activity"]["runtime"]["periodCloseEvents"], 0)
        self.assertEqual(mission(report)["activity"]["unspecified"]["periodCloseEvents"], 1)

    def test_latest_capabilities_and_native_window_gates_keep_source_references(self):
        log = Log().begin().snapshot()
        path = 'snapshot["capabilities"]["finance"]'
        log.add("dump.value", {"path": path, "value": False})
        log.add("dump.value", {"path": path, "value": True})
        log.add("dump.value", {"path": 'snapshot["finance"]["windowStatus"]', "value": "unverified"})
        log.add("underwriting.gate", {"status": "withheld", "completePeriodCount": 0})
        report = log.finish().report()
        m = mission(report)
        self.assertTrue(m["latestCapabilities"][path]["value"])
        self.assertEqual(m["latestGates"]['snapshot["finance"]["windowStatus"]']["value"], "unverified")
        self.assertIn("require independent native validation", analyzer.render_markdown(report))

    def test_save_stage_counts_do_not_claim_independent_saves(self):
        log = Log().begin().snapshot()
        log.add("history.save.begin", {"transactionId": 8})
        log.add("history.save.end", {"transactionId": 8, "stage": "sidecar_write_returned", "written": True})
        log.add("history.save.end", {"transactionId": 8, "stage": "native_callback_returned"})
        report = log.finish().report()
        activity = mission(report)["activity"]["runtime"]
        self.assertEqual(activity["saveIds"], 1)
        self.assertEqual(activity["saveEndEvents"], 2)

    def test_missing_catalog_remains_explicit_and_runtime_coverage_is_retained(self):
        log = Log().begin().snapshot().finish()
        report = log.report(catalog={"status": "unavailable", "checks": []})
        self.assertIn("CATALOG_UNAVAILABLE", codes(report))
        self.assertEqual(len(mission(report)["scenarioCoverage"]), 2)
        no_summary = Log().begin().report(catalog={"status": "unavailable", "checks": []})
        self.assertIn("CATALOG_NOT_SUPPLIED", codes(no_summary))

    def test_catalog_parser_reads_real_catalog_and_refuses_unknown_layout(self):
        catalog = analyzer.load_catalog()
        self.assertEqual(catalog["status"], "available")
        self.assertGreater(len(catalog["checks"]), 100)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "catalog.lua"
            path.write_text('BankValidationCatalog = {checks={{id="NEW-001", arbitraryCall()}}}', encoding="utf-8")
            self.assertEqual(analyzer.load_catalog(path)["status"], "partial")

    def test_bounded_summary_failure_reserve_retains_failures_after_log_budget(self):
        log = Log().begin().snapshot().check("EXISTING", "FAIL")
        metadata = {"failureIds": {"EXISTING": {"FAIL": 1}, "LOST": {"FAIL": 2}, "SYNTHETIC_LOST": {"FAIL": 1}},
                    "totalFailedChecks": 3, "failureListTruncated": False, "dropped": 4}
        log.summary({"EXISTING": {"FAIL": 1}}, **metadata)
        report = log.add("mission.end").summary(**metadata).report()
        m = mission(report)
        self.assertEqual(m["checks"]["runtime:EXISTING"]["counts"]["FAIL"], 1)
        self.assertEqual(m["checks"]["runtime:LOST"]["counts"]["FAIL"], 2)
        self.assertEqual(m["checks"]["synthetic:SYNTHETIC_LOST"]["counts"]["FAIL"], 1)
        synthetic_failure = next(row for row in m["failureEvidence"] if row.get("id") == "SYNTHETIC_LOST")
        self.assertEqual(synthetic_failure["origin"], "synthetic")
        self.assertEqual(synthetic_failure["envelopeOrigin"], "runtime")
        self.assertEqual(m["reportedFailedCheckIds"], 3)
        self.assertIn("SUMMARY_FAILURE_WITHOUT_EVENT", codes(report))
        self.assertIn("3 failed check IDs", analyzer.render_markdown(report))

    def test_bounded_failure_list_truncation_not_silently_lost(self):
        report = Log().begin().snapshot().add("mission.end").summary(
            failureIds={"ONE": {"FAIL": 1}}, totalFailedChecks=17, failureListTruncated=True).report()
        self.assertIn("FAILURE_LIST_TRUNCATED", codes(report))
        self.assertIn("17 failed check IDs", analyzer.render_markdown(report))

    def test_pre_mission_mode_record_does_not_invent_missing_lifecycle(self):
        log = Log(mission=0).add("debug.mode", {"mode": "on"})
        log.mission = 1
        report = log.begin().snapshot().finish().report()
        self.assertEqual(report["integrity"], "CAPTURED")
        self.assertEqual(mission(report)["context"], "pre-mission diagnostics")
        only_startup = Log(mission=0).add("debug.mode", {"mode": "on"}).report()
        self.assertIn("NO_RUNTIME_MISSION", codes(only_startup))

    def test_successful_capture_requires_dump_failed_capture_is_not_usable(self):
        log = Log().begin().add("capture.begin").add("capture.end", {"ok": True})
        self.assertIn("MISSING_SNAPSHOT_DUMP", codes(log.finish().report()))
        failed = Log().begin().add("capture.begin").add("capture.end", {"ok": False}).finish().report()
        self.assertIn("CAPTURE_FAILED", codes(failed))
        self.assertIn("NO_COMPLETE_RUNTIME_CAPTURE", codes(failed))
        self.assertEqual(len(mission(failed)["failureEvidence"]), 1)

    def test_post_summary_transaction_requires_new_summary(self):
        log = Log().begin().snapshot().summary().add("history.transaction.begin", {"transactionId": 9}).add("mission.end")
        self.assertIn("STALE_SUMMARY", codes(log.report()))

    def test_duplicate_json_key_cannot_overwrite_failure_claim(self):
        log = Log().begin()
        log.lines.append(analyzer.PREFIX + ' {"schema":1,"seq":2,"mission":1,"capture":0,"event":"check","origin":"runtime","data":{"id":"C","outcome":"FAIL","outcome":"PASS"}}')
        report = log.report()
        self.assertIn("MALFORMED_JSON", codes(report))
        self.assertFalse(mission(report)["checks"])

    def test_cli_markdown_json_outputs_and_cannot_overwrite_original(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            source, md, js = directory / "log.txt", directory / "report.md", directory / "report.json"
            contents = "\n".join(Log().begin().snapshot().finish().lines)
            source.write_text(contents, encoding="utf-8")
            result = subprocess.run([sys.executable, str(ROOT / "tools" / "analyze_log.py"), str(source), "--output", str(md), "--json", str(js)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "")
            self.assertIn("INCOMPLETE validation coverage", md.read_text(encoding="utf-8"))
            self.assertEqual(json.loads(js.read_text(encoding="utf-8"))["integrity"], "CAPTURED")
            result = subprocess.run([sys.executable, str(ROOT / "tools" / "analyze_log.py"), str(source), "--output", str(source)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(source.read_text(encoding="utf-8"), contents)


if __name__ == "__main__":
    unittest.main()
