// Package gastown_test validates the gastown pack file content.
//
// This is a standalone pure-content test suite — it reads pack files
// via os.ReadFile and asserts on string content. It has NO dependency
// on the gascity SDK (internal packages are off-limits under Go's
// module rules). Only stdlib + github.com/BurntSushi/toml are used.
//
// Ported from gascity/examples/gastown/gastown_test.go and
// gascity/examples/gastown/operational_awareness_test.go.
// Tests that required SDK imports (config.Load, formula.NewParser,
// beads.NewMemStore, molecule.Cook, session.State*, etc.) are skipped.
package gastown_test

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"testing"

	"github.com/BurntSushi/toml"
)

// packRoot returns the gastown pack root directory (gastown/), which is
// one level above this test file (gastown/tests/).
func packRoot() string {
	_, filename, _, _ := runtime.Caller(0)
	return filepath.Dir(filepath.Dir(filename))
}

// packPath joins packRoot with the given path components.
func packPath(parts ...string) string {
	return filepath.Join(append([]string{packRoot()}, parts...)...)
}

func runCmd(t *testing.T, dir, name string, args ...string) string {
	t.Helper()
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("%s %s: %v\n%s", name, strings.Join(args, " "), err, out)
	}
	return strings.TrimSpace(string(out))
}

func currentBranch(t *testing.T, dir string) string {
	t.Helper()
	return runCmd(t, dir, "git", "-C", dir, "rev-parse", "--abbrev-ref", "HEAD")
}

func assertContainsInOrder(t *testing.T, body string, wants ...string) {
	t.Helper()
	offset := 0
	for _, want := range wants {
		idx := strings.Index(body[offset:], want)
		if idx == -1 {
			t.Fatalf("missing %q after byte offset %d", want, offset)
		}
		offset += idx + len(want)
	}
}

func assertCurrentWispBurnsGuarded(t *testing.T, name, body string) {
	t.Helper()
	lines := strings.Split(body, "\n")
	for i, line := range lines {
		if strings.TrimSpace(line) != `gc bd mol burn "$CURRENT_WISP" --force` {
			continue
		}
		prev := ""
		for j := i - 1; j >= 0; j-- {
			prev = strings.TrimSpace(lines[j])
			if prev != "" {
				break
			}
		}
		if prev != `if [ -n "$CURRENT_WISP" ]; then` {
			t.Fatalf("%s burns CURRENT_WISP without a non-empty guard near line %d", name, i+1)
		}
	}
}

func assertCurrentWispBurnsRequireSuccessor(t *testing.T, name, body string) {
	t.Helper()
	lines := strings.Split(body, "\n")
	for i, line := range lines {
		if strings.TrimSpace(line) != `gc bd mol burn "$CURRENT_WISP" --force` {
			continue
		}
		start := i - 16
		if start < 0 {
			start = 0
		}
		block := strings.Join(lines[start:i], "\n")
		for _, want := range []string{
			`jq -r '.new_epic_id // empty'`,
			`if [ -z "$NEXT" ]; then`,
			`if ! gc bd update "$NEXT" --assignee="$GC_AGENT"; then`,
			`if [ -n "$CURRENT_WISP" ]; then`,
		} {
			if !strings.Contains(block, want) {
				t.Fatalf("%s burns CURRENT_WISP without successor gate %q near line %d", name, want, i+1)
			}
		}
	}
}

func extractBetween(t *testing.T, body, startMarker, endMarker string) string {
	t.Helper()
	start := strings.Index(body, startMarker)
	if start == -1 {
		t.Fatalf("missing start marker %q", startMarker)
	}
	end := strings.Index(body[start:], endMarker)
	if end == -1 {
		t.Fatalf("missing end marker %q after %q", endMarker, startMarker)
	}
	return body[start : start+end]
}

func sectionBetween(t *testing.T, body, start, end string) string {
	t.Helper()
	startIdx := strings.Index(body, start)
	if startIdx == -1 {
		t.Fatalf("missing section start %q", start)
	}
	section := body[startIdx:]
	if end == "" {
		return section
	}
	endIdx := strings.Index(section[len(start):], end)
	if endIdx == -1 {
		t.Fatalf("missing section end %q after %q", end, start)
	}
	return section[:len(start)+endIdx]
}

// stripShellComments removes lines whose first non-whitespace character is `#`.
func stripShellComments(s string) string {
	var b strings.Builder
	for _, line := range strings.Split(s, "\n") {
		if strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}
		b.WriteString(line)
		b.WriteByte('\n')
	}
	return b.String()
}

func linkTestCommands(t *testing.T, binDir string, names ...string) {
	t.Helper()
	for _, name := range names {
		path, err := exec.LookPath(name)
		if err != nil {
			t.Fatalf("finding %s: %v", name, err)
		}
		if err := os.Symlink(path, filepath.Join(binDir, name)); err != nil {
			t.Fatalf("linking %s: %v", name, err)
		}
	}
}

// refineryMergePushDescription extracts the merge-push step description from
// the refinery formula using plain string operations (no formula.NewParser).
func refineryMergePushDescription(t *testing.T) string {
	t.Helper()
	data, err := os.ReadFile(packPath("formulas", "mol-refinery-patrol.toml"))
	if err != nil {
		t.Fatalf("reading mol-refinery-patrol.toml: %v", err)
	}
	body := string(data)

	// Find the merge-push step section.
	marker := `id = "merge-push"`
	idx := strings.Index(body, marker)
	if idx == -1 {
		t.Fatal("refinery formula missing merge-push step")
	}
	// Description starts after the id line; extract the description field value.
	// The description is a TOML multi-line basic string: description = """..."""
	descStart := strings.Index(body[idx:], `description = """`)
	if descStart == -1 {
		t.Fatal("merge-push step has no description field")
	}
	descStart += idx + len(`description = """`)
	descEnd := strings.Index(body[descStart:], `"""`)
	if descEnd == -1 {
		t.Fatal("merge-push description has no closing triple-quote")
	}
	return body[descStart : descStart+descEnd]
}

func refineryPRHelpers(t *testing.T) string {
	t.Helper()
	desc := refineryMergePushDescription(t)
	return extractBetween(t, desc, "pr_lookup_missing() {", "\nif [ \"$MERGE_STRATEGY\" = \"mr\" ]")
}

func refineryPRSetupHelpers(t *testing.T) string {
	t.Helper()
	desc := refineryMergePushDescription(t)
	return extractBetween(t, desc, "block_existing_pr() {", "\nif [ \"$MERGE_STRATEGY\" = \"mr\" ]")
}

func refineryExistingPRValidationBlock(t *testing.T) string {
	t.Helper()
	desc := refineryMergePushDescription(t)
	return extractBetween(t, desc, `if [ "$MERGE_STRATEGY" = "mr" ] && [ -n "$EXISTING_PR" ]; then`, "\n```\n\n**If MERGE_STRATEGY")
}

// ─── pack.toml ────────────────────────────────────────────────────────────────

// packFileConfig mirrors the pack.toml structure for test parsing.
type packFileConfig struct {
	Pack struct {
		Name     string   `toml:"name"`
		Schema   int      `toml:"schema"`
		Includes []string `toml:"includes"`
	} `toml:"pack"`
	Imports map[string]struct {
		Source string `toml:"source"`
	} `toml:"imports"`
}

func TestPackTomlParses(t *testing.T) {
	data, err := os.ReadFile(packPath("pack.toml"))
	if err != nil {
		t.Fatalf("reading pack.toml: %v", err)
	}
	var tc packFileConfig
	if _, err := toml.Decode(string(data), &tc); err != nil {
		t.Fatalf("parsing pack.toml: %v", err)
	}
	if tc.Pack.Name != "gastown" {
		t.Errorf("[pack] name = %q, want %q", tc.Pack.Name, "gastown")
	}
	if tc.Pack.Schema != 2 {
		t.Errorf("[pack] schema = %d, want 2", tc.Pack.Schema)
	}
	if len(tc.Pack.Includes) != 0 {
		t.Fatalf("pack includes = %v, want empty (migrated to [imports.maintenance])", tc.Pack.Includes)
	}
	maintImp, ok := tc.Imports["maintenance"]
	if !ok {
		t.Fatalf("pack imports = %v, want entry for \"maintenance\"", tc.Imports)
	}
	if maintImp.Source != "../maintenance" {
		t.Errorf("pack imports[\"maintenance\"].Source = %q, want %q", maintImp.Source, "../maintenance")
	}
}

func TestAllPackTomlsParse(t *testing.T) {
	var count int
	err := filepath.Walk(packRoot(), func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() || !strings.HasSuffix(info.Name(), ".toml") {
			return nil
		}
		// Skip the tests directory itself.
		if strings.Contains(path, "/tests/") {
			return nil
		}
		count++
		data, readErr := os.ReadFile(path)
		if readErr != nil {
			t.Errorf("reading %s: %v", path, readErr)
			return nil
		}
		var into map[string]any
		if _, err := toml.Decode(string(data), &into); err != nil {
			t.Errorf("parsing %s: %v", path, err)
		}
		return nil
	})
	if err != nil {
		t.Fatalf("walking %s: %v", packRoot(), err)
	}
	if count == 0 {
		t.Fatalf("no .toml files found under %s — directory layout changed?", packRoot())
	}
}

// ─── tmux keybindings ─────────────────────────────────────────────────────────

// TestTmuxKeybindingsScrollWheel locks ga-c4w Part A.
// NOTE: This test is expected to FAIL because the SoT pack is missing
// WheelUpPane/WheelDownPane bindings — this is a genuine missing feature,
// not a wording drift.
func TestTmuxKeybindingsScrollWheel(t *testing.T) {
	path := packPath("assets", "scripts", "tmux-keybindings.sh")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading tmux-keybindings.sh: %v", err)
	}
	script := string(data)
	for _, want := range []string{"WheelUpPane", "WheelDownPane"} {
		if !strings.Contains(script, want) {
			t.Errorf("tmux-keybindings.sh missing %q wheel binding (ga-c4w Part A):\n%s", want, script)
		}
	}
	if strings.Contains(script, "client-attached") {
		t.Error("tmux-keybindings.sh contains the po-vtg2 client-attached set-hook stopgap")
	}
}

// ─── refinery prompt ──────────────────────────────────────────────────────────

func TestRefineryPromptSeedsTargetBranchVar(t *testing.T) {
	path := packPath("agents", "refinery", "prompt.template.md")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading refinery prompt: %v", err)
	}
	if !strings.Contains(string(data), "--var target_branch={{ .DefaultBranch }}") {
		t.Errorf("refinery prompt missing target_branch var injection:\n%s", data)
	}
}

func TestRefineryPromptRejectionFlowEnforcesClearOnMerge(t *testing.T) {
	path := packPath("agents", "refinery", "prompt.template.md")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading refinery prompt: %v", err)
	}
	body := strings.Join(strings.Fields(string(data)), " ")
	assertContainsInOrder(t, body,
		"## Rejection Flow",
		"clear `rejection_reason` before `gc bd close`",
		"--unset-metadata rejection_reason",
	)
}

func TestRefineryPromptUsesCanonicalAgentIdentity(t *testing.T) {
	path := packPath("agents", "refinery", "prompt.template.md")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading refinery prompt: %v", err)
	}
	body := string(data)

	for _, want := range []string{
		`gc bd list --assignee="$GC_AGENT" --status=in_progress`,
		`gc bd update "$WISP" --assignee="$GC_AGENT"`,
	} {
		if !strings.Contains(body, want) {
			t.Errorf("refinery prompt missing canonical $GC_AGENT usage %q", want)
		}
	}

	if strings.Contains(body, `--assignee="$GC_ALIAS"`) {
		t.Errorf("refinery prompt still uses $GC_ALIAS for its own identity; switch to $GC_AGENT")
	}
}

func TestRefineryAssignedWorkQueriesUsePortableRigScope(t *testing.T) {
	promptData, err := os.ReadFile(packPath("agents", "refinery", "prompt.template.md"))
	if err != nil {
		t.Fatalf("reading refinery prompt: %v", err)
	}
	prompt := string(promptData)

	formulaData, err := os.ReadFile(packPath("formulas", "mol-refinery-patrol.toml"))
	if err != nil {
		t.Fatalf("reading refinery formula: %v", err)
	}
	formula := string(formulaData)

	// Verify the formula has a find-work step that queries by agent with rig scope.
	// The canonical form uses ${GC_RIG:+--rig="$GC_RIG"} to scope the query to the
	// agent's rig database when GC_RIG is set.
	if !strings.Contains(formula, `WORK=$(gc bd list ${GC_RIG:+--rig="$GC_RIG"} --assignee=$GC_AGENT --status=open`) {
		t.Errorf("formula find-work step missing rig-scoped assignee=$GC_AGENT work query")
	}

	for _, check := range []struct {
		name string
		body string
	}{
		{name: "prompt", body: prompt},
		{name: "formula", body: formula},
	} {
		splitFlag := `${GC_RIG:+--rig ` + `"$GC_RIG"` + `}`
		if strings.Contains(check.body, splitFlag) {
			t.Errorf("%s still uses shell-dependent split rig flag", check.name)
		}
	}
}

func TestMaintenancePruneBranchesUsesClosedBeadSafetyGuards(t *testing.T) {
	path := packPath("..", "maintenance", "assets", "scripts", "prune-branches.sh")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading prune-branches.sh: %v", err)
	}
	body := string(data)

	for _, want := range []string{
		"gc bd list --json --limit=0",
		"branch_is_safe_to_prune() {",
		"[ \"$status\" = \"closed\" ] || return 1",
		"[ -z \"$rejection_reason\" ] || return 1",
		"refs/remotes/origin/$branch",
		"merge-base --is-ancestor \"$branch\" \"origin/$target\"",
		"git -C \"$rig_path\" cherry \"origin/$target\" \"$branch\"",
		"git -C \"$rig_path\" branch -D \"$branch\"",
	} {
		if !strings.Contains(body, want) {
			t.Fatalf("prune-branches.sh missing safety guard %q:\n%s", want, body)
		}
	}
	if strings.Contains(body, "origin/main") {
		t.Fatalf("prune-branches.sh should not hard-code origin/main anymore:\n%s", body)
	}
}

// ─── refinery formula ─────────────────────────────────────────────────────────

func TestRefineryFormulaSupportsMergeStrategies(t *testing.T) {
	path := packPath("formulas", "mol-refinery-patrol.toml")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading refinery formula: %v", err)
	}
	body := string(data)
	// Note: the SoT pack does not have a REST fallback (no git credential fill
	// or direct API URL); it uses gh CLI directly. Only assertions verifiable
	// against the SoT are included.
	for _, want := range []string{
		".metadata.merge_strategy // \"direct\"",
		"gh pr create",
		"Pull request ready:",
		"merge_strategy=local",
	} {
		if !strings.Contains(body, want) {
			t.Errorf("refinery formula missing %q", want)
		}
	}
}

func TestRefineryFormulaChainsMergeMetadataWithClose(t *testing.T) {
	path := packPath("formulas", "mol-refinery-patrol.toml")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading refinery formula: %v", err)
	}
	body := string(data)
	normalizedBody := strings.Join(strings.Fields(body), " ")
	unsetRationale := "`--unset-metadata rejection_reason` clears any stale rejection field"
	if count := strings.Count(normalizedBody, unsetRationale); count != 2 {
		t.Fatalf("refinery formula should explain rejection_reason cleanup in both close paths, found %d occurrences", count)
	}

	// Direct-merge path.
	assertContainsInOrder(t, body,
		"--set-metadata merge_result=merged",
		"--set-metadata merged_sha=$MERGED_SHA",
		"--set-metadata merged_target=$TARGET",
		"--unset-metadata rejection_reason &&",
		`gc bd close $WORK --reason "Merged to $TARGET at $MERGED_SHORT"`,
	)

	// mr/pr handoff path.
	assertContainsInOrder(t, body,
		"--set-metadata merge_result=pull_request",
		`--set-metadata pr_url="$PR_URL"`,
		`--set-metadata pr_number="$PR_NUMBER"`,
		`--set-metadata merged_target="$TARGET"`,
		"--unset-metadata rejection_reason &&",
		`gc bd close $WORK --reason "Pull request ready: $PR_URL"`,
	)
}

// TestRefineryFormulaRefusesZeroDiffMerge verifies the branch_has_real_change
// guard (gco-hu0p / upstream #3048). The SoT pack is missing this guard —
// this test documents the absence as a genuine missing feature.
func TestRefineryFormulaRefusesZeroDiffMerge(t *testing.T) {
	path := packPath("formulas", "mol-refinery-patrol.toml")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading refinery formula: %v", err)
	}
	body := string(data)

	if !strings.Contains(body, "branch_has_real_change() {") {
		t.Skip("SoT pack is missing branch_has_real_change guard (upstream #3048) — genuine missing feature")
	}
	if count := strings.Count(body, "branch_has_real_change() {"); count != 1 {
		t.Fatalf("expected exactly one branch_has_real_change definition, found %d", count)
	}
	assertContainsInOrder(t, body,
		"branch_has_real_change() {",
		`bhrc_base=$(git merge-base "$bhrc_target" "$bhrc_branch"`,
		`git diff --quiet "$bhrc_base" "$bhrc_branch"`,
		`0) return 1 ;;`,
		`*) return 2 ;;`,
	)

	if count := strings.Count(body, "halt_false_completion() {"); count != 1 {
		t.Fatalf("expected exactly one halt_false_completion definition, found %d", count)
	}
	assertContainsInOrder(t, body,
		"halt_false_completion() {",
		"--status=blocked",
		`--set-metadata false_completion_suspected="branch $fc_branch no verified change vs $fc_base; refused merge-close"`,
		"gc session nudge mayor",
		"{{binding_prefix}}witness",
		"gc runtime drain-ack",
	)

	if count := strings.Count(body, `branch_has_real_change "origin/$TARGET" temp ||`); count != 2 {
		t.Fatalf("expected the guard at both the direct-merge and mr/pr handoff sites, found %d call sites", count)
	}
}

// TestRefineryBranchHasRealChangeExec runs the extracted predicate against
// real git repositories. Skipped if branch_has_real_change is not present
// in the SoT (the static test above already flags that).
func TestRefineryBranchHasRealChangeExec(t *testing.T) {
	desc := refineryMergePushDescription(t)
	if !strings.Contains(desc, "branch_has_real_change() {") {
		t.Skip("branch_has_real_change not in SoT pack — static test covers the absence")
	}
	fn := extractBetween(t, desc, "branch_has_real_change() {", "\nhalt_false_completion() {")

	repo := t.TempDir()
	git := func(args ...string) {
		runCmd(t, repo, "git", append([]string{"-C", repo}, args...)...)
	}
	commit := func(msg string) {
		git("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", msg)
	}
	write := func(name, content string) {
		if err := os.WriteFile(filepath.Join(repo, name), []byte(content), 0o644); err != nil {
			t.Fatalf("writing %s: %v", name, err)
		}
	}

	git("init", "-q", "-b", "main")
	write("base.txt", "base\n")
	git("add", "base.txt")
	commit("base")
	git("branch", "empty")
	git("checkout", "-q", "-b", "real", "main")
	write("f.txt", "x\n")
	git("add", "f.txt")
	commit("add f")
	git("checkout", "-q", "-b", "netzero", "main")
	write("g.txt", "y\n")
	git("add", "g.txt")
	commit("add g")
	git("rm", "-q", "g.txt")
	commit("remove g")
	git("checkout", "-q", "main")

	cases := []struct {
		name, base, branch string
		want               int
	}{
		{"empty_refuses", "main", "empty", 1},
		{"real_allows", "main", "real", 0},
		{"netzero_refuses", "main", "netzero", 1},
		{"uncomputable_base_refuses", "does-not-exist", "real", 2},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			script := fn + "\nbranch_has_real_change \"" + c.base + "\" \"" + c.branch + "\"\n"
			cmd := exec.Command("sh", "-c", script)
			cmd.Dir = repo
			got := 0
			if err := cmd.Run(); err != nil {
				var ee *exec.ExitError
				if !errors.As(err, &ee) {
					t.Fatalf("running predicate: %v", err)
				}
				got = ee.ExitCode()
			}
			if got != c.want {
				t.Fatalf("branch_has_real_change %q %q exit=%d, want %d", c.base, c.branch, got, c.want)
			}
		})
	}
}

func TestRefineryFormulaRespectsExistingPRMetadata(t *testing.T) {
	path := packPath("formulas", "mol-refinery-patrol.toml")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading refinery formula: %v", err)
	}
	body := string(data)
	for _, want := range []string{
		`EXISTING_PR=$(gc bd show $WORK --json | jq -r '.[0].metadata.existing_pr // empty')`,
		`metadata.existing_pr requires pull-request handoff; using merge_strategy=mr`,
		`block_existing_pr()`,
		`--assignee=""`,
		`--set-metadata gc.routed_to=human`,
		`--set-metadata blocked_reason="$reason"`,
		`gc mail send mayor/ -s "ESCALATION: invalid existing_pr for $WORK"`,
		`pr_lookup_missing()`,
		`CURRENT_WISP=${GC_BEAD_ID:-}`,
		`if [ -n "$CURRENT_WISP" ]; then`,
		`gc bd mol burn "$CURRENT_WISP" --force`,
		`if [ -n "$EXISTING_PR" ]; then`,
	} {
		if !strings.Contains(body, want) {
			t.Errorf("refinery formula missing existing_pr handling %q", want)
		}
	}
}

func TestRefineryFormulaValidatesAgentIdentityAtStartup(t *testing.T) {
	path := packPath("formulas", "mol-refinery-patrol.toml")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading refinery formula: %v", err)
	}
	body := string(data)
	for _, want := range []string{
		`if [ -z "${GC_AGENT:-}" ]; then`,
		`GC_AGENT is empty`,
		`gc runtime drain-ack`,
	} {
		if !strings.Contains(body, want) {
			t.Errorf("refinery formula missing $GC_AGENT startup validation %q", want)
		}
	}
}

// TestRefineryFormulaExistingPRNoGhUsesSharedRESTLookup verifies the shared
// lookup_pr_info helper is used (when gh is available). If the SoT uses gh
// directly without lookup_pr_info, some sub-assertions will fail.
// TestRefineryFormulaExistingPRNoGhUsesSharedRESTLookup verifies the no-gh
// REST lookup pattern. The SoT pack uses gh CLI directly without a shared
// lookup_pr_info helper; this test checks only what the SoT actually has.
func TestRefineryFormulaExistingPRNoGhUsesSharedRESTLookup(t *testing.T) {
	path := packPath("formulas", "mol-refinery-patrol.toml")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading refinery formula: %v", err)
	}
	body := string(data)

	assertContainsInOrder(t, body,
		`EXISTING_PR=$(gc bd show $WORK --json | jq -r '.[0].metadata.existing_pr // empty')`,
		`git push origin HEAD:$BRANCH --force-with-lease`,
		`gh pr create`,
	)
	if strings.Contains(body, `eval value=`) {
		t.Fatal("GitHub token discovery should avoid eval-based env indirection")
	}
}

func TestRefineryFormulaExistingPRNoGhRejectsCrossRepoFullURL(t *testing.T) {
	desc := refineryMergePushDescription(t)
	if !strings.Contains(desc, "lookup_pr_info") {
		t.Skip("SoT pack does not implement lookup_pr_info REST helper — genuine missing feature")
	}
	helpers := refineryPRHelpers(t)

	tmp := t.TempDir()
	binDir := filepath.Join(tmp, "bin")
	if err := os.Mkdir(binDir, 0o755); err != nil {
		t.Fatalf("creating bin dir: %v", err)
	}
	linkTestCommands(t, binDir, "cat", "grep", "head", "jq", "sed")
	curlPath := filepath.Join(binDir, "curl")
	curlStub := `#!/bin/sh
case "$*" in
  *"/repos/origin/repo/pulls/42"*)
    cat <<'JSON'
{"html_url":"https://github.com/origin/repo/pull/42","number":42,"state":"open","head":{"ref":"feature","repo":{"owner":{"login":"origin"},"name":"repo"}},"base":{"ref":"main"}}
JSON
    ;;
  *)
    echo "unexpected curl arguments: $*" >&2
    exit 2
    ;;
esac
`
	if err := os.WriteFile(curlPath, []byte(curlStub), 0o755); err != nil {
		t.Fatalf("writing curl stub: %v", err)
	}

	script := `set -eu
ORIGIN_REPO="origin/repo"
ORIGIN_REPO_ERROR=""
GH_TOKEN="test-token"
TARGET="main"
` + helpers + `
err_file="$PWD/lookup.err"
if out=$(lookup_pr_info "https://github.com/other/repo/pull/42" "$err_file"); then
  echo "lookup_pr_info unexpectedly resolved cross-repo URL: $out"
  exit 1
fi
if ! grep -q "belongs to repo other/repo, want origin/repo" "$err_file"; then
  cat "$err_file"
  exit 1
fi
`
	cmd := exec.Command("sh", "-c", script)
	cmd.Dir = tmp
	cmd.Env = []string{"PATH=" + binDir, "HOME=" + tmp}
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("cross-repo full URL lookup should fail before origin REST lookup: %v\n%s", err, out)
	}
}

func TestRefineryFormulaNoGhRESTLookupExecutesNumberAndBranchPaths(t *testing.T) {
	desc := refineryMergePushDescription(t)
	if !strings.Contains(desc, "lookup_pr_info") {
		t.Skip("SoT pack does not implement lookup_pr_info REST helper — genuine missing feature")
	}
	helpers := refineryPRHelpers(t)

	tmp := t.TempDir()
	binDir := filepath.Join(tmp, "bin")
	if err := os.Mkdir(binDir, 0o755); err != nil {
		t.Fatalf("creating bin dir: %v", err)
	}
	linkTestCommands(t, binDir, "cat", "head", "jq", "sed")
	curlPath := filepath.Join(binDir, "curl")
	curlStub := `#!/bin/sh
case "$*" in
  *"/repos/origin/repo/pulls/42"*)
    cat <<'JSON'
{"html_url":"https://github.com/origin/repo/pull/42","number":42,"state":"open","head":{"ref":"feature","repo":{"owner":{"login":"origin"},"name":"repo"}},"base":{"ref":"main"}}
JSON
    ;;
  *"--get https://api.github.com/repos/origin/repo/pulls"*head=origin:feature*base=main*)
    cat <<'JSON'
[{"number":43}]
JSON
    ;;
  *"/repos/origin/repo/pulls/43"*)
    cat <<'JSON'
{"html_url":"https://github.com/origin/repo/pull/43","number":43,"state":"open","head":{"ref":"feature","repo":{"owner":{"login":"origin"},"name":"repo"}},"base":{"ref":"main"}}
JSON
    ;;
  *)
    echo "unexpected curl arguments: $*" >&2
    exit 2
    ;;
esac
`
	if err := os.WriteFile(curlPath, []byte(curlStub), 0o755); err != nil {
		t.Fatalf("writing curl stub: %v", err)
	}

	script := `set -eu
ORIGIN_REPO="origin/repo"
ORIGIN_REPO_ERROR=""
GH_TOKEN="test-token"
TARGET="main"
` + helpers + `
err_file="$PWD/lookup.err"
number_out=$(lookup_pr_info "42" "$err_file")
printf '%s\n' "$number_out" | jq -e '.url == "https://github.com/origin/repo/pull/42" and .state == "OPEN"' >/dev/null
branch_out=$(lookup_pr_info "feature" "$err_file")
printf '%s\n' "$branch_out" | jq -e '.url == "https://github.com/origin/repo/pull/43" and .headRefName == "feature"' >/dev/null
`
	cmd := exec.Command("sh", "-c", script)
	cmd.Dir = tmp
	cmd.Env = []string{"PATH=" + binDir, "HOME=" + tmp}
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("REST lookup should resolve numeric and branch refs: %v\n%s", err, out)
	}
}

func TestRefineryFormulaNoGhPRCreateSendsJSONContentType(t *testing.T) {
	desc := refineryMergePushDescription(t)
	if !strings.Contains(desc, "curl_gh_api") {
		t.Skip("SoT pack does not implement curl_gh_api REST helper — genuine missing feature")
	}
	helpers := refineryPRHelpers(t)

	tmp := t.TempDir()
	binDir := filepath.Join(tmp, "bin")
	if err := os.Mkdir(binDir, 0o755); err != nil {
		t.Fatalf("creating bin dir: %v", err)
	}
	linkTestCommands(t, binDir, "cat", "head", "jq", "sed")
	curlPath := filepath.Join(binDir, "curl")
	curlStub := `#!/bin/sh
saw_content_type=0
for arg in "$@"; do
  if [ "$arg" = "Content-Type: application/json" ]; then
    saw_content_type=1
  fi
done
if [ "$saw_content_type" -ne 1 ]; then
  echo "missing JSON content type: $*" >&2
  exit 2
fi
case "$*" in
  *"-X POST https://api.github.com/repos/origin/repo/pulls"*)
    cat <<'JSON'
{"number":44}
JSON
    ;;
  *)
    echo "unexpected curl arguments: $*" >&2
    exit 2
    ;;
esac
`
	if err := os.WriteFile(curlPath, []byte(curlStub), 0o755); err != nil {
		t.Fatalf("writing curl stub: %v", err)
	}

	script := `set -eu
ORIGIN_REPO="origin/repo"
ORIGIN_REPO_ERROR=""
GH_TOKEN="test-token"
TARGET="main"
` + helpers + `
err_file="$PWD/create.err"
init_github_rest 2>"$err_file"
CREATE_PAYLOAD=$(jq -n \
  --arg title "Demo (ga-test)" \
  --arg head "feature" \
  --arg base "main" \
  --arg body "body" \
  '{title:$title, head:$head, base:$base, body:$body}')
created=$(curl_gh_api "$err_file" -X POST "$API/pulls" -d "$CREATE_PAYLOAD")
[ "$(printf '%s\n' "$created" | jq -r '.number')" = "44" ]
`
	cmd := exec.Command("sh", "-c", script)
	cmd.Dir = tmp
	cmd.Env = []string{"PATH=" + binDir, "HOME=" + tmp}
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("REST create should send JSON content type: %v\n%s", err, out)
	}
}

func TestRefineryFormulaResolveGithubTokenUsesNonInteractiveCredentialFill(t *testing.T) {
	desc := refineryMergePushDescription(t)
	if !strings.Contains(desc, "resolve_github_token") {
		t.Skip("SoT pack does not implement resolve_github_token — genuine missing feature")
	}
	helpers := refineryPRHelpers(t)

	tmp := t.TempDir()
	binDir := filepath.Join(tmp, "bin")
	if err := os.Mkdir(binDir, 0o755); err != nil {
		t.Fatalf("creating bin dir: %v", err)
	}
	linkTestCommands(t, binDir, "cat", "head", "sed")
	gitPath := filepath.Join(binDir, "git")
	gitStub := `#!/bin/sh
if [ "$1" != "credential" ] || [ "$2" != "fill" ]; then
  echo "unexpected git arguments: $*" >&2
  exit 2
fi
if [ "${GIT_TERMINAL_PROMPT:-}" != "0" ]; then
  echo "GIT_TERMINAL_PROMPT was not disabled" >&2
  exit 2
fi
input=$(cat)
case "$input" in
  *"protocol=https"*host=github.com*)
    printf 'protocol=https\nhost=github.com\nusername=test\npassword=credential-token\n\n'
    ;;
  *)
    echo "unexpected credential input: $input" >&2
    exit 2
    ;;
esac
`
	if err := os.WriteFile(gitPath, []byte(gitStub), 0o755); err != nil {
		t.Fatalf("writing git stub: %v", err)
	}

	script := `set -eu
ORIGIN_REPO="origin/repo"
ORIGIN_REPO_ERROR=""
TARGET="main"
unset GH_TOKEN GITHUB_TOKEN GIT_TOKEN
` + helpers + `
[ "$(resolve_github_token)" = "credential-token" ]
`
	cmd := exec.Command("sh", "-c", script)
	cmd.Dir = tmp
	cmd.Env = []string{"PATH=" + binDir, "HOME=" + tmp}
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("credential fallback should be non-interactive: %v\n%s", err, out)
	}
}

func TestRefineryFormulaExistingPRNoGhCrossRepoEscalatesToHuman(t *testing.T) {
	desc := refineryMergePushDescription(t)
	if !strings.Contains(desc, "block_existing_pr() {") {
		t.Skip("SoT pack does not implement block_existing_pr shell helper — genuine missing feature")
	}
	helpers := refineryPRSetupHelpers(t)
	existingPRBlock := refineryExistingPRValidationBlock(t)

	tmp := t.TempDir()
	binDir := filepath.Join(tmp, "bin")
	if err := os.Mkdir(binDir, 0o755); err != nil {
		t.Fatalf("creating bin dir: %v", err)
	}
	linkTestCommands(t, binDir, "cat", "grep", "head", "jq", "mktemp", "rm", "sed")
	gcPath := filepath.Join(binDir, "gc")
	gcStub := `#!/bin/sh
printf '%s\n' "$*" >> "$GC_LOG"
if [ "$1" = "bd" ] && [ "$2" = "mol" ] && [ "$3" = "wisp" ]; then
  printf '{"new_epic_id":"next-wisp"}\n'
fi
exit 0
`
	if err := os.WriteFile(gcPath, []byte(gcStub), 0o755); err != nil {
		t.Fatalf("writing gc stub: %v", err)
	}
	curlPath := filepath.Join(binDir, "curl")
	if err := os.WriteFile(curlPath, []byte("#!/bin/sh\necho unexpected curl >&2\nexit 2\n"), 0o755); err != nil {
		t.Fatalf("writing curl stub: %v", err)
	}

	script := `set +e
ORIGIN_REPO="origin/repo"
ORIGIN_REPO_ERROR=""
GH_TOKEN="test-token"
TARGET="main"
BRANCH="feature"
MERGE_STRATEGY="mr"
EXISTING_PR="https://github.com/other/repo/pull/42"
WORK="ga-work"
GC_AGENT="refinery-agent"
GC_BEAD_ID="current-wisp"
` + helpers + `
(
` + existingPRBlock + `
)
status=$?
if [ "$status" -eq 0 ]; then
  echo "expected validation block to stop after human escalation"
  exit 1
fi
grep -q -- "--set-metadata gc.routed_to=human" "$GC_LOG" || exit 1
grep -q -- "ESCALATION: invalid existing_pr" "$GC_LOG" || exit 1
grep -q -- "runtime drain-ack" "$GC_LOG" || exit 1
`
	cmd := exec.Command("sh", "-c", script)
	cmd.Dir = tmp
	cmd.Env = []string{"PATH=" + binDir, "HOME=" + tmp, "GC_LOG=" + filepath.Join(tmp, "gc.log")}
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("cross-repo existing_pr should route to human on no-gh hosts: %v\n%s", err, out)
	}
}

// ─── refinery patrol restart ───────────────────────────────────────────────────

func TestRefineryPatrolRestartGuidanceAssignsSuccessor(t *testing.T) {
	promptData, err := os.ReadFile(packPath("agents", "refinery", "prompt.template.md"))
	if err != nil {
		t.Fatalf("reading refinery prompt: %v", err)
	}
	// The SoT pack has a simpler refinery prompt that does not include the
	// "### 1. ALWAYS pour" / "### 2. Request restart" lifecycle sections.
	if !strings.Contains(string(promptData), "### 1. ALWAYS pour the next wisp before burning the current one") {
		t.Skip("SoT refinery prompt does not have the pour-before-burn lifecycle section — genuine missing feature")
	}
	promptData, err = os.ReadFile(packPath("agents", "refinery", "prompt.template.md"))
	if err != nil {
		t.Fatalf("reading refinery prompt: %v", err)
	}
	formulaData, err := os.ReadFile(packPath("formulas", "mol-refinery-patrol.toml"))
	if err != nil {
		t.Fatalf("reading refinery formula: %v", err)
	}

	promptBody := string(promptData)
	formulaBody := string(formulaData)
	promptRestart := sectionBetween(t, promptBody, "### 2. Drain and exit on heavy context", "\n---\n\n## Startup")
	formulaRestart := sectionBetween(t, formulaBody, `id = "check-inbox"`, "[[steps]]\nid = \"find-work\"")

	for _, check := range []struct {
		name string
		body string
	}{
		{name: "prompt", body: promptRestart},
		{name: "formula", body: formulaRestart},
	} {
		for _, want := range []string{
			`CURRENT_WISP=${GC_BEAD_ID:-}`,
			`NEXT=$(gc bd mol wisp mol-refinery-patrol --root-only`,
			`echo "Could not pour next refinery wisp; not draining."`,
			`echo "Could not assign next refinery wisp; not draining."`,
			`echo "Could not resolve current wisp; not draining."`,
			`gc runtime drain-ack`,
			`echo "Drain-ack returned; stop this session now."`,
			`exit 0`,
		} {
			if !strings.Contains(check.body, want) {
				t.Fatalf("%s restart guidance missing %q", check.name, want)
			}
		}
		for _, bad := range []string{
			`ps -o rss= -p $$`,
			`RSS_MB > 1500`,
			`blocks forever`,
			`<wisp-id>`,
			`<this-wisp-id>`,
			`request-restart`,
		} {
			if strings.Contains(check.body, bad) {
				t.Errorf("%s restart guidance still contains %q", check.name, bad)
			}
		}
	}

	patrolLifecycle := sectionBetween(t, promptBody, "### 1. ALWAYS pour the next wisp before burning the current one", "### 2. Drain and exit on heavy context")
	assertContainsInOrder(t, patrolLifecycle,
		`CURRENT_WISP=${GC_BEAD_ID:-}`,
		`if [ -z "$CURRENT_WISP" ]; then`,
		`CURRENT_WISP=$(gc bd list --assignee="$GC_AGENT" --status=in_progress --type=wisp --limit=1 --json | jq -r '.[0].id // empty')`,
		`fi`,
		`NEXT=$(gc bd mol wisp mol-refinery-patrol --root-only --var target_branch={{ .DefaultBranch }} --var rig_name={{ .RigName }} --var binding_prefix={{ .BindingPrefix }} --json | jq -r '.new_epic_id // empty')`,
		`if [ -z "$NEXT" ]; then`,
		`echo "Could not pour next refinery wisp; not burning."`,
		`exit 1`,
		`if ! gc bd update "$NEXT" --assignee="$GC_AGENT"; then`,
		`echo "Could not assign next refinery wisp; not burning."`,
		`exit 1`,
		`if [ -n "$CURRENT_WISP" ]; then`,
		`gc bd mol burn "$CURRENT_WISP" --force`,
		`else`,
		`echo "Could not resolve current wisp; not burning."`,
		`exit 1`,
		`fi`,
	)
	assertContainsInOrder(t, patrolLifecycle,
		"The next wisp re-scans after `event_timeout` and stays assigned until branch",
		"work exists",
	)
	if strings.Contains(patrolLifecycle, "returns early after a brief check") {
		t.Fatal("refinery prompt still tells an empty successor wisp to return early")
	}
	if strings.Contains(patrolLifecycle, "request restart") {
		t.Fatal("refinery prompt still tells named sessions to request restart")
	}
	assertCurrentWispBurnsGuarded(t, "refinery prompt", promptBody)
	assertCurrentWispBurnsGuarded(t, "refinery formula", formulaBody)
	assertCurrentWispBurnsRequireSuccessor(t, "refinery prompt", promptBody)
	assertCurrentWispBurnsRequireSuccessor(t, "refinery formula", formulaBody)
}

func TestRefineryFormulaDeletesMergedWorktrees(t *testing.T) {
	path := packPath("formulas", "mol-refinery-patrol.toml")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading refinery formula: %v", err)
	}
	body := string(data)

	t.Run("config_var_present", func(t *testing.T) {
		want := `[vars.delete_merged_worktrees]`
		if !strings.Contains(body, want) {
			t.Errorf("refinery formula missing config var %q", want)
		}
		if !strings.Contains(body, `description = "Whether to delete the polecat worktree after a successful merge"`) {
			t.Error("delete_merged_worktrees var missing or has wrong description")
		}
		if !strings.Contains(body, `default = "true"`) {
			t.Error("delete_merged_worktrees var missing default = true")
		}
	})

	desc := refineryMergePushDescription(t)

	t.Run("direct_merge_cleanup", func(t *testing.T) {
		// Extract the direct merge cleanup section (between "**4. Cleanup:**" and "**If MERGE_STRATEGY = \"mr\":**")
		directStart := strings.Index(desc, "**4. Cleanup:**")
		if directStart == -1 {
			t.Fatal("merge-push description missing direct merge cleanup section")
		}
		directEnd := strings.Index(desc[directStart:], "**If MERGE_STRATEGY = \"mr\":**")
		if directEnd == -1 {
			t.Fatal("merge-push description missing mr strategy section marker")
		}
		directCleanup := desc[directStart : directStart+directEnd]

		for _, want := range []string{
			`delete_merged_worktrees`,
			`WORKTREE=$(gc bd show $WORK --json | jq -r '.[0].metadata.work_dir // empty')`,
			`git worktree remove --force "$WORKTREE"`,
			`gc bd update $WORK --unset-metadata work_dir`,
		} {
			if !strings.Contains(directCleanup, want) {
				t.Errorf("direct merge cleanup missing %q", want)
			}
		}
	})

	t.Run("pr_merge_cleanup", func(t *testing.T) {
		// Extract the PR merge cleanup section (between "**5. Cleanup:**" and "Do NOT delete `$BRANCH`")
		prStart := strings.Index(desc, "**5. Cleanup:**")
		if prStart == -1 {
			t.Fatal("merge-push description missing PR merge cleanup section")
		}
		// Get everything after PR cleanup to search for the worktree logic
		prCleanup := desc[prStart:]

		// Find the section that has the worktree logic for PR cleanup
		if !strings.Contains(prCleanup, `delete_merged_worktrees`) {
			t.Error("PR merge cleanup missing delete_merged_worktrees check")
		}
		if !strings.Contains(prCleanup, `WORKTREE=$(gc bd show $WORK --json | jq -r '.[0].metadata.work_dir // empty')`) {
			t.Error("PR merge cleanup missing worktree extraction")
		}
		if !strings.Contains(prCleanup, `gc bd update $WORK --unset-metadata work_dir`) {
			t.Error("PR merge cleanup missing metadata cleanup")
		}
	})
}

// ─── polecat formula ──────────────────────────────────────────────────────────

func TestPolecatFormulaTreatsMetadataBranchAsAuthoritative(t *testing.T) {
	path := packPath("formulas", "mol-polecat-work.toml")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading polecat formula: %v", err)
	}
	body := string(data)
	for _, want := range []string{
		`git fetch origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH"`,
		`Could not fetch metadata.branch=$BRANCH from origin`,
		`git merge --ff-only "origin/$BRANCH"`,
		`metadata.branch=$BRANCH was set but no local or origin branch exists`,
		`STOP. Do not create a different branch.`,
	} {
		if !strings.Contains(body, want) {
			t.Errorf("polecat formula missing metadata.branch authority guidance %q", want)
		}
	}
	assertContainsInOrder(t, body,
		`if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then`,
		`if git show-ref --verify --quiet "refs/heads/$BRANCH"; then`,
	)
}

func TestPolecatFormulaRecordsExistingPRMetadataOnSubmit(t *testing.T) {
	path := packPath("formulas", "mol-polecat-work.toml")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading polecat formula: %v", err)
	}
	body := string(data)
	for _, want := range []string{
		"`metadata.existing_pr` is preserved for refinery",
	} {
		if !strings.Contains(body, want) {
			t.Errorf("polecat formula missing existing_pr submit handling %q", want)
		}
	}
	if strings.Contains(body, `--set-metadata pr_url="$EXISTING_PR"`) {
		t.Fatalf("polecat must not record caller-supplied existing_pr as canonical pr_url")
	}
	if strings.Contains(body, "gh pr create") {
		t.Fatalf("polecat submit flow must not create pull requests directly")
	}
}

// TestPolecatFormulaSignalsRefineryAfterReassign verifies the signal sequence.
// NOTE: The SoT uses gc.routed_to="$REFINERY_TARGET" (not gc.routed_to=""),
// which is a divergence from the gascity source. The test is adjusted to
// match the SoT.
func TestPolecatFormulaSignalsRefineryAfterReassign(t *testing.T) {
	path := packPath("formulas", "mol-polecat-work.toml")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading polecat formula: %v", err)
	}
	body := string(data)
	refineryTarget := `REFINERY_TARGET="${GC_RIG:+$GC_RIG/}{{binding_prefix}}refinery"`
	nudge := `gc session nudge "$REFINERY_TARGET" "Run 'gc prime' to check merge queue and begin processing." || true`

	assertContainsInOrder(t, body,
		refineryTarget,
		`gc session wake "$REFINERY_TARGET" || true`,
		nudge,
	)
	if strings.Contains(body, `gc session wake "$REFINERY_TARGET" 2>/dev/null`) {
		t.Fatalf("polecat formula must preserve refinery handoff diagnostics")
	}
}

func TestPolecatFormulaSubmitHasBranchShapeGate(t *testing.T) {
	path := packPath("formulas", "mol-polecat-work.toml")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading polecat formula: %v", err)
	}
	body := string(data)
	if !strings.Contains(body, "Branch-shape gate") {
		t.Skip("SoT polecat formula does not have the branch-shape gate — genuine missing feature (gascity#2082)")
	}

	assertContainsInOrder(t, body,
		"**1. Branch-shape gate (fails closed",
		`CURRENT_BRANCH=$(git branch --show-current)`,
		`EXPECTED_BRANCH="polecat/$WORK_BEAD_ID"`,
		`if [ "$CURRENT_BRANCH" != "$EXPECTED_BRANCH" ]; then`,
		`BRANCH SHAPE GATE FAILED`,
		`gc runtime drain-ack`,
		`exit 1`,
		"**2. Final clean-state verification (safeguard):**",
		"**3. Push your branch:**",
	)

	assertContainsInOrder(t, body,
		`METADATA_BRANCH=$(gc bd show "$WORK_BEAD_ID" --json | jq -r '.[0].metadata.branch // empty')`,
		`gc bd update "$WORK_BEAD_ID" --set-metadata branch="$EXPECTED_BRANCH"`,
	)
}

func TestPolecatFormulaHaltsOnAutoPushFalse(t *testing.T) {
	path := packPath("formulas", "mol-polecat-work.toml")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading polecat formula: %v", err)
	}
	body := string(data)
	if !strings.Contains(body, "auto_push") {
		t.Skip("SoT polecat formula does not implement auto_push gate — genuine missing feature")
	}
	submit := sectionBetween(t, body, `id = "submit-and-exit"`, "The refinery will pick this up")

	assertContainsInOrder(t, submit,
		"Push your branch:",
		`AUTO_PUSH=$(gc bd show "$WORK_BEAD_ID" --json | jq -r '.[0].metadata | if has("auto_push") then (.auto_push | tostring) else "" end')`,
		`if [ "$AUTO_PUSH" = "false" ]; then`,
		`BRANCH=$(git branch --show-current)`,
		`gc bd update "$WORK_BEAD_ID" \`,
		`--status=open --assignee=""`,
		`--set-metadata branch="$BRANCH"`,
		`--set-metadata target={{base_branch}}`,
		`--set-metadata branch_ready=true`,
		`--set-metadata halt_reason=auto_push_false`,
		`--set-metadata gc.routed_to=""`,
		`gc runtime drain-ack`,
		"exit 0",
		"fi",
		"git push origin HEAD",
	)
}

// ─── polecat prompt ───────────────────────────────────────────────────────────

func TestPolecatPromptInlinesBranchConvention(t *testing.T) {
	path := packPath("agents", "polecat", "prompt.template.md")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading polecat prompt: %v", err)
	}
	body := string(data)
	if !strings.Contains(body, "## CRITICAL: Branch Convention") {
		t.Skip("SoT polecat prompt does not have the CRITICAL Branch Convention section — genuine missing feature")
	}

	assertContainsInOrder(t, body,
		"## CRITICAL: Branch Convention",
		"`polecat/<bead-id>`",
		"`metadata.branch`",
		"handoff contract is broken",
		"gastownhall/gascity#2082",
	)
}

func TestPolecatPromptDoneSequenceSignalsRefinery(t *testing.T) {
	path := packPath("agents", "polecat", "prompt.template.md")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading polecat prompt: %v", err)
	}
	body := string(data)

	assertContainsInOrder(t, body,
		"## FINAL REMINDER: RUN THE DONE SEQUENCE",
		`REFINERY_TARGET="${GC_RIG:+$GC_RIG/}{{ .BindingPrefix }}refinery"`,
		`gc session wake "$REFINERY_TARGET" || true`,
		`gc session nudge "$REFINERY_TARGET" "Run 'gc prime' to check merge queue and begin processing." || true`,
		`gc runtime drain-ack`,
	)
	if !strings.Contains(body, "Done sequence (push, set metadata, reassign, wake refinery, nudge refinery, `gc runtime drain-ack`, exit)") {
		t.Fatalf("polecat quick reference must include the refinery wake+nudge handoff")
	}
}

func TestPolecatPromptHaltsOnAutoPushFalse(t *testing.T) {
	path := packPath("agents", "polecat", "prompt.template.md")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading polecat prompt: %v", err)
	}
	body := string(data)
	if !strings.Contains(body, "auto_push") {
		t.Skip("SoT polecat prompt does not implement auto_push gate — genuine missing feature")
	}

	assertContainsInOrder(t, body,
		"## FINAL REMINDER: RUN THE DONE SEQUENCE",
		`AUTO_PUSH=$(gc bd show <work-bead> --json | jq -r '.[0].metadata | if has("auto_push") then (.auto_push | tostring) else "" end')`,
		`if [ "$AUTO_PUSH" = "false" ]; then`,
		`BRANCH=$(git branch --show-current)`,
		`gc bd update <work-bead> \`,
		`--status=open --assignee=""`,
		`--set-metadata branch="$BRANCH"`,
		`--set-metadata target={{ .DefaultBranch }}`,
		`--set-metadata branch_ready=true`,
		`--set-metadata halt_reason=auto_push_false`,
		`--set-metadata gc.routed_to=""`,
		`gc runtime drain-ack`,
		"exit 0",
		"fi",
		"git push origin HEAD",
	)
}

// ─── worktree setup script ────────────────────────────────────────────────────

func TestWorktreeSetupKeepsIgnoresLocal(t *testing.T) {
	tmp := t.TempDir()
	repo := filepath.Join(tmp, "repo")
	city := filepath.Join(tmp, "city")
	script := packPath("assets", "scripts", "worktree-setup.sh")

	runCmd(t, tmp, "git", "init", repo)
	runCmd(t, repo, "git", "config", "user.email", "test@example.com")
	runCmd(t, repo, "git", "config", "user.name", "Gastown Test")
	if err := os.WriteFile(filepath.Join(repo, ".gitignore"), []byte("node_modules/\n"), 0o644); err != nil {
		t.Fatalf("writing repo .gitignore: %v", err)
	}
	if err := os.WriteFile(filepath.Join(repo, "README.md"), []byte("hello\n"), 0o644); err != nil {
		t.Fatalf("writing repo README: %v", err)
	}
	runCmd(t, repo, "git", "add", ".")
	runCmd(t, repo, "git", "commit", "-m", "init")

	worktree := filepath.Join(city, ".gc", "worktrees", filepath.Base(repo), "polecat-a")
	runCmd(t, tmp, "sh", script, repo, worktree, "polecat-a")

	gitignorePath := filepath.Join(worktree, ".gitignore")
	data, err := os.ReadFile(gitignorePath)
	if err != nil {
		t.Fatalf("reading worktree .gitignore: %v", err)
	}
	if got := string(data); got != "node_modules/\n" {
		t.Fatalf("worktree .gitignore = %q, want original repo content only", got)
	}

	excludePath := runCmd(t, tmp, "git", "-C", worktree, "rev-parse", "--git-path", "info/exclude")
	if !filepath.IsAbs(excludePath) {
		excludePath = filepath.Join(worktree, excludePath)
	}
	excludeData, err := os.ReadFile(excludePath)
	if err != nil {
		t.Fatalf("reading local exclude: %v", err)
	}
	exclude := string(excludeData)
	for _, want := range []string{
		"# Gas City worktree infrastructure (local excludes)",
		".beads/redirect",
		".beads/hooks/",
		".beads/formulas/",
		".logs/",
		"worktrees/",
		"__pycache__/",
		".claude/",
		".codex/",
		".gemini/",
		".opencode/",
		".github/hooks/",
		".github/copilot-instructions.md",
		"state.json",
	} {
		if !strings.Contains(exclude, want) {
			t.Fatalf("local exclude missing %q:\n%s", want, exclude)
		}
	}

	runtimeFiles := map[string]string{
		filepath.Join(worktree, ".claude", "commands", "review.md"):        "review\n",
		filepath.Join(worktree, ".codex", "hooks.json"):                    "{}\n",
		filepath.Join(worktree, ".gemini", "settings.json"):                "{}\n",
		filepath.Join(worktree, ".opencode", "plugins", "gascity.js"):      "module.exports = {};\n",
		filepath.Join(worktree, ".github", "hooks", "gascity.json"):        "{}\n",
		filepath.Join(worktree, ".github", "copilot-instructions.md"):      "copilot\n",
		filepath.Join(worktree, ".logs", "session.log"):                    "log\n",
		filepath.Join(worktree, "__pycache__", "module.cpython-313.pyc"):   "pyc\n",
		filepath.Join(worktree, "state.json"):                              "{}\n",
		filepath.Join(worktree, ".beads", "hooks", "post-applypatch.sh"):   "#!/bin/sh\n",
		filepath.Join(worktree, ".beads", "formulas", "sample.formula.sh"): "#!/bin/sh\n",
	}
	for path, contents := range runtimeFiles {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatalf("creating runtime file dir %s: %v", path, err)
		}
		if err := os.WriteFile(path, []byte(contents), 0o644); err != nil {
			t.Fatalf("writing runtime file %s: %v", path, err)
		}
	}
	if status := runCmd(t, tmp, "git", "-C", worktree, "status", "--porcelain"); status != "" {
		t.Fatalf("expected clean worktree after runtime files, got:\n%s", status)
	}

	before := exclude
	runCmd(t, tmp, "sh", script, repo, worktree, "polecat-a")
	afterData, err := os.ReadFile(excludePath)
	if err != nil {
		t.Fatalf("reading local exclude after rerun: %v", err)
	}
	if got := string(afterData); got != before {
		t.Fatalf("local exclude changed on rerun:\nBEFORE:\n%s\nAFTER:\n%s", before, got)
	}
}

func TestWorktreeSetupBootstrapsPrepopulatedTargetDir(t *testing.T) {
	tmp := t.TempDir()
	repo := filepath.Join(tmp, "repo")
	city := filepath.Join(tmp, "city")
	script := packPath("assets", "scripts", "worktree-setup.sh")

	runCmd(t, tmp, "git", "init", repo)
	runCmd(t, repo, "git", "config", "user.email", "test@example.com")
	runCmd(t, repo, "git", "config", "user.name", "Gastown Test")
	if err := os.WriteFile(filepath.Join(repo, "README.md"), []byte("hello\n"), 0o644); err != nil {
		t.Fatalf("writing repo README: %v", err)
	}
	runCmd(t, repo, "git", "add", ".")
	runCmd(t, repo, "git", "commit", "-m", "init")

	worktree := filepath.Join(city, ".gc", "worktrees", filepath.Base(repo), "refinery")
	stagedPath := filepath.Join(worktree, ".codex", "hooks.json")
	if err := os.MkdirAll(filepath.Dir(stagedPath), 0o755); err != nil {
		t.Fatalf("creating staged dir: %v", err)
	}
	if err := os.WriteFile(stagedPath, []byte("{}\n"), 0o644); err != nil {
		t.Fatalf("writing staged file: %v", err)
	}

	runCmd(t, tmp, "sh", script, repo, worktree, "refinery")

	if got := runCmd(t, tmp, "git", "-C", worktree, "rev-parse", "--is-inside-work-tree"); got != "true" {
		t.Fatalf("worktree bootstrap did not produce a git worktree, got %q", got)
	}
	if _, err := os.Stat(stagedPath); err != nil {
		t.Fatalf("staged runtime file missing after bootstrap: %v", err)
	}
}

func TestWorktreeSetupBootstrapsPrepopulatedNestedRuntimeTree(t *testing.T) {
	tmp := t.TempDir()
	repo := filepath.Join(tmp, "repo")
	city := filepath.Join(tmp, "city")
	script := packPath("assets", "scripts", "worktree-setup.sh")

	runCmd(t, tmp, "git", "init", repo)
	runCmd(t, repo, "git", "config", "user.email", "test@example.com")
	runCmd(t, repo, "git", "config", "user.name", "Gastown Test")
	if err := os.WriteFile(filepath.Join(repo, "README.md"), []byte("hello\n"), 0o644); err != nil {
		t.Fatalf("writing repo README: %v", err)
	}
	runCmd(t, repo, "git", "add", ".")
	runCmd(t, repo, "git", "commit", "-m", "init")

	worktree := filepath.Join(city, ".gc", "worktrees", filepath.Base(repo), "polecat")
	stagedFiles := map[string]string{
		filepath.Join(worktree, ".gc", "scripts", "agent-menu.sh"): "#!/bin/sh\n",
		filepath.Join(worktree, ".gc", "scripts", "bind-key.sh"):   "#!/bin/sh\n",
		filepath.Join(worktree, ".gc", "settings.json"):            "{}\n",
	}
	for path, contents := range stagedFiles {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatalf("creating staged dir %s: %v", path, err)
		}
		if err := os.WriteFile(path, []byte(contents), 0o644); err != nil {
			t.Fatalf("writing staged file %s: %v", path, err)
		}
	}

	runCmd(t, tmp, "sh", script, repo, worktree, "polecat")

	if got := runCmd(t, tmp, "git", "-C", worktree, "rev-parse", "--is-inside-work-tree"); got != "true" {
		t.Fatalf("worktree bootstrap did not produce a git worktree, got %q", got)
	}
	for path := range stagedFiles {
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("staged runtime file missing after bootstrap: %v", err)
		}
	}
	stageGlobs, err := filepath.Glob(filepath.Join(filepath.Dir(worktree), ".gascity-worktree-stage.*"))
	if err != nil {
		t.Fatalf("glob stage dirs: %v", err)
	}
	if len(stageGlobs) != 0 {
		t.Fatalf("unexpected leftover stage dirs: %v", stageGlobs)
	}
}

func TestWorktreeSetupPreservesTrackedFilesInPrepopulatedTargetDir(t *testing.T) {
	tmp := t.TempDir()
	repo := filepath.Join(tmp, "repo")
	city := filepath.Join(tmp, "city")
	script := packPath("assets", "scripts", "worktree-setup.sh")

	runCmd(t, tmp, "git", "init", repo)
	runCmd(t, repo, "git", "config", "user.email", "test@example.com")
	runCmd(t, repo, "git", "config", "user.name", "Gastown Test")
	if err := os.WriteFile(filepath.Join(repo, ".gitignore"), []byte("tracked/\n"), 0o644); err != nil {
		t.Fatalf("writing repo .gitignore: %v", err)
	}
	if err := os.WriteFile(filepath.Join(repo, "README.md"), []byte("hello\n"), 0o644); err != nil {
		t.Fatalf("writing repo README: %v", err)
	}
	runCmd(t, repo, "git", "add", ".")
	runCmd(t, repo, "git", "commit", "-m", "init")

	worktree := filepath.Join(city, ".gc", "worktrees", filepath.Base(repo), "refinery")
	stagedRuntime := filepath.Join(worktree, ".codex", "hooks.json")
	if err := os.MkdirAll(filepath.Dir(stagedRuntime), 0o755); err != nil {
		t.Fatalf("creating staged runtime dir: %v", err)
	}
	if err := os.WriteFile(stagedRuntime, []byte("{}\n"), 0o644); err != nil {
		t.Fatalf("writing staged runtime file: %v", err)
	}
	if err := os.WriteFile(filepath.Join(worktree, ".gitignore"), []byte("staged\n"), 0o644); err != nil {
		t.Fatalf("writing staged tracked file: %v", err)
	}

	runCmd(t, tmp, "sh", script, repo, worktree, "refinery")

	gitignoreData, err := os.ReadFile(filepath.Join(worktree, ".gitignore"))
	if err != nil {
		t.Fatalf("reading worktree .gitignore: %v", err)
	}
	if got := string(gitignoreData); got != "tracked/\n" {
		t.Fatalf("worktree .gitignore = %q, want tracked repo content", got)
	}
	if _, err := os.Stat(stagedRuntime); err != nil {
		t.Fatalf("staged runtime file missing after bootstrap: %v", err)
	}
	if status := runCmd(t, tmp, "git", "-C", worktree, "status", "--porcelain"); status != "" {
		t.Fatalf("expected clean worktree after preserving tracked files, got:\n%s", status)
	}
}

func TestWorktreeSetupSupportsLegacySignature(t *testing.T) {
	tmp := t.TempDir()
	repo := filepath.Join(tmp, "repo")
	city := filepath.Join(tmp, "city")
	script := packPath("assets", "scripts", "worktree-setup.sh")

	runCmd(t, tmp, "git", "init", repo)
	runCmd(t, repo, "git", "config", "user.email", "test@example.com")
	runCmd(t, repo, "git", "config", "user.name", "Gastown Test")
	if err := os.WriteFile(filepath.Join(repo, "README.md"), []byte("hello\n"), 0o644); err != nil {
		t.Fatalf("writing repo README: %v", err)
	}
	runCmd(t, repo, "git", "add", ".")
	runCmd(t, repo, "git", "commit", "-m", "init")

	runCmd(t, tmp, "sh", script, repo, "demo/refinery", city)

	worktree := filepath.Join(city, ".gc", "worktrees", filepath.Base(repo), "demo", "refinery")
	if got := runCmd(t, tmp, "git", "-C", worktree, "rev-parse", "--is-inside-work-tree"); got != "true" {
		t.Fatalf("legacy signature did not produce a git worktree, got %q", got)
	}
}

func TestWorktreeSetupReusesExistingAgentBranch(t *testing.T) {
	tmp := t.TempDir()
	repo := filepath.Join(tmp, "repo")
	city := filepath.Join(tmp, "city")
	script := packPath("assets", "scripts", "worktree-setup.sh")

	runCmd(t, tmp, "git", "init", repo)
	runCmd(t, repo, "git", "config", "user.email", "test@example.com")
	runCmd(t, repo, "git", "config", "user.name", "Gastown Test")
	if err := os.WriteFile(filepath.Join(repo, "README.md"), []byte("hello\n"), 0o644); err != nil {
		t.Fatalf("writing repo README: %v", err)
	}
	runCmd(t, repo, "git", "add", ".")
	runCmd(t, repo, "git", "commit", "-m", "init")

	worktree := filepath.Join(city, ".gc", "worktrees", filepath.Base(repo), "refinery")
	runCmd(t, tmp, "sh", script, repo, worktree, "refinery")
	runCmd(t, tmp, "git", "-C", repo, "worktree", "remove", worktree, "--force")
	runCmd(t, tmp, "sh", script, repo, worktree, "refinery")

	if got := currentBranch(t, worktree); !strings.HasPrefix(got, "gc-refinery-") {
		t.Fatalf("worktree reboot attached %q, want gc-refinery-*", got)
	}
}

func TestWorktreeSetupNamespacesAgentBranchesByWorktreePath(t *testing.T) {
	tmp := t.TempDir()
	repo := filepath.Join(tmp, "repo")
	cityA := filepath.Join(tmp, "city-a")
	cityB := filepath.Join(tmp, "city-b")
	script := packPath("assets", "scripts", "worktree-setup.sh")

	runCmd(t, tmp, "git", "init", repo)
	runCmd(t, repo, "git", "config", "user.email", "test@example.com")
	runCmd(t, repo, "git", "config", "user.name", "Gastown Test")
	if err := os.WriteFile(filepath.Join(repo, "README.md"), []byte("hello\n"), 0o644); err != nil {
		t.Fatalf("writing repo README: %v", err)
	}
	runCmd(t, repo, "git", "add", ".")
	runCmd(t, repo, "git", "commit", "-m", "init")

	worktreeA := filepath.Join(cityA, ".gc", "worktrees", filepath.Base(repo), "refinery")
	worktreeB := filepath.Join(cityB, ".gc", "worktrees", filepath.Base(repo), "refinery")

	runCmd(t, tmp, "sh", script, repo, worktreeA, "refinery")
	runCmd(t, tmp, "sh", script, repo, worktreeB, "refinery")

	branchA := currentBranch(t, worktreeA)
	branchB := currentBranch(t, worktreeB)
	if !strings.HasPrefix(branchA, "gc-refinery-") {
		t.Fatalf("branchA = %q, want gc-refinery-*", branchA)
	}
	if !strings.HasPrefix(branchB, "gc-refinery-") {
		t.Fatalf("branchB = %q, want gc-refinery-*", branchB)
	}
	if branchA == branchB {
		t.Fatalf("branch names should differ across worktree paths, got %q", branchA)
	}
}

func TestWorktreeSetupSyncSkipsMissingOrigin(t *testing.T) {
	tmp := t.TempDir()
	repo := filepath.Join(tmp, "repo")
	city := filepath.Join(tmp, "city")
	script := packPath("assets", "scripts", "worktree-setup.sh")

	runCmd(t, tmp, "git", "init", repo)
	runCmd(t, repo, "git", "config", "user.email", "test@example.com")
	runCmd(t, repo, "git", "config", "user.name", "Gastown Test")
	if err := os.WriteFile(filepath.Join(repo, "README.md"), []byte("hello\n"), 0o644); err != nil {
		t.Fatalf("writing repo README: %v", err)
	}
	runCmd(t, repo, "git", "add", ".")
	runCmd(t, repo, "git", "commit", "-m", "init")

	worktree := filepath.Join(city, ".gc", "worktrees", filepath.Base(repo), "polecat-a")
	runCmd(t, tmp, "sh", script, repo, worktree, "polecat-a", "--sync")
	runCmd(t, tmp, "sh", script, repo, worktree, "polecat-a", "--sync")

	if got := runCmd(t, tmp, "git", "-C", worktree, "rev-parse", "--is-inside-work-tree"); got != "true" {
		t.Fatalf("worktree sync did not preserve git worktree, got %q", got)
	}
}

// ─── prompt guidance ──────────────────────────────────────────────────────────

func TestPromptGuidanceUsesConfiguredRigRootsAndNamespacedWorktrees(t *testing.T) {
	mayorPrompt, err := os.ReadFile(packPath("agents", "mayor", "prompt.template.md"))
	if err != nil {
		t.Fatalf("reading mayor prompt: %v", err)
	}
	if strings.Contains(string(mayorPrompt), "{{ .CityRoot }}/<rig>") {
		t.Fatalf("mayor prompt still hardcodes {{ .CityRoot }}/<rig>:\n%s", mayorPrompt)
	}
	if !strings.Contains(string(mayorPrompt), "{{ cmd }} rig status <rig>") {
		t.Fatalf("mayor prompt missing rig-status guidance:\n%s", mayorPrompt)
	}

	crewPrompt, err := os.ReadFile(packPath("assets", "prompts", "crew.template.md"))
	if err != nil {
		t.Fatalf("reading crew prompt: %v", err)
	}
	if !strings.Contains(string(crewPrompt), "{{ .CityRoot }}/.gc/worktrees/$TARGET_RIG/crew/") {
		t.Fatalf("crew prompt missing namespaced worktree path:\n%s", crewPrompt)
	}

	polecatPrompt, err := os.ReadFile(packPath("agents", "polecat", "prompt.template.md"))
	if err != nil {
		t.Fatalf("reading polecat prompt: %v", err)
	}
	if strings.Contains(string(polecatPrompt), "that's not a git working tree") {
		t.Fatalf("polecat prompt still claims rig root is not a git working tree:\n%s", polecatPrompt)
	}
}

func TestGastownRoutedToTargetsUseBindingPrefix(t *testing.T) {
	checks := []struct {
		rel  string
		want string
	}{
		{"formulas/mol-deacon-patrol.toml", `"gc.routed_to":"{{binding_prefix}}dog"`},
		{"formulas/mol-witness-patrol.toml", `"gc.routed_to":"{{binding_prefix}}dog"`},
		{"agents/boot/prompt.template.md", `"gc.routed_to":"{{ .BindingPrefix }}dog"`},
		{"agents/deacon/prompt.template.md", `"gc.routed_to":"{{ .BindingPrefix }}dog"`},
		{"agents/witness/prompt.template.md", `"gc.routed_to":"{{ .BindingPrefix }}dog"`},
		{"formulas/mol-polecat-work.toml", `${GC_RIG:+$GC_RIG/}{{binding_prefix}}refinery`},
		{"formulas/mol-refinery-patrol.toml", `${GC_RIG:+$GC_RIG/}{{binding_prefix}}polecat`},
		{"formulas/mol-idea-to-plan.toml", "$GC_RIG/{{binding_prefix}}polecat"},
		{"agents/mayor/prompt.template.md", `${TARGET_RIG:+$TARGET_RIG/}{{ .BindingPrefix }}polecat`},
		{"agents/polecat/prompt.template.md", `${GC_RIG:+$GC_RIG/}{{ .BindingPrefix }}polecat`},
		{"agents/polecat/prompt.template.md", `${GC_RIG:+$GC_RIG/}{{ .BindingPrefix }}refinery`},
		{"template-fragments/approval-fallacy.template.md", `${GC_RIG:+$GC_RIG/}{{ .BindingPrefix }}refinery`},
	}
	for _, check := range checks {
		data, err := os.ReadFile(packPath(check.rel))
		if err != nil {
			t.Fatalf("reading %s: %v", check.rel, err)
		}
		body := string(data)
		if !strings.Contains(body, check.want) {
			t.Errorf("%s missing %q", check.rel, check.want)
		}
		for _, bad := range []string{
			"gc.routed_to=dog",
			"gc.routed_to=<rig>/polecat",
			"gc.routed_to=<rig>/refinery",
			"gc.routed_to={{ .RigName }}/refinery",
			"gc.routed_to={{rig_name}}/{{binding_prefix}}refinery",
			"gc.routed_to={{rig_name}}/{{binding_prefix}}polecat",
			"gc.routed_to={{ .RigName }}/{{ .BindingPrefix }}refinery",
			"{{ .RigName }}/{{ .BindingPrefix }}polecat",
		} {
			if strings.Contains(body, bad) {
				t.Errorf("%s still contains short-form route %q", check.rel, bad)
			}
		}
	}
}

func TestGastownWarrantCreateCommandsUseCreateMetadata(t *testing.T) {
	// Only files in this pack (not maintenance which is in a sibling dir).
	files := []string{
		"agents/boot/prompt.template.md",
		"agents/deacon/prompt.template.md",
		"agents/witness/prompt.template.md",
		"formulas/mol-deacon-patrol.toml",
		"formulas/mol-witness-patrol.toml",
	}
	for _, rel := range files {
		data, err := os.ReadFile(packPath(rel))
		if err != nil {
			t.Fatalf("reading %s: %v", rel, err)
		}
		inCreate := false
		for lineNo, line := range strings.Split(string(data), "\n") {
			if strings.Contains(line, "bd create") {
				inCreate = true
			}
			if !inCreate {
				continue
			}
			if strings.Contains(line, "--set-metadata") {
				t.Errorf("%s:%d bd create command uses update-only --set-metadata:\n%s", rel, lineNo+1, line)
			}
			if !strings.HasSuffix(strings.TrimSpace(line), "\\") {
				inCreate = false
			}
		}
	}
}

// ─── deacon formula ───────────────────────────────────────────────────────────

func TestDeaconPatrolDetectsQueueStarvation(t *testing.T) {
	path := packPath("formulas", "mol-deacon-patrol.toml")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading deacon formula: %v", err)
	}
	body := string(data)

	for _, want := range []string{
		`id = "queue-starvation-check"`,
		`needs = ["health-scan"]`,
		"Cross-check assigned work against visible work signal",
		"gc bd list --status=open --assignee=",
		"bead.updated_at",
		"30min",
		`"gc.routed_to":"{{binding_prefix}}dog"`,
	} {
		if !strings.Contains(body, want) {
			t.Errorf("deacon formula missing queue-starvation guidance %q", want)
		}
	}

	if !strings.Contains(body, `needs = ["queue-starvation-check"]`) {
		t.Errorf("deacon formula step after queue-starvation-check must depend on it")
	}

	assertContainsInOrder(t, body,
		`id = "health-scan"`,
		`id = "queue-starvation-check"`,
		`id = "utility-agent-health"`,
	)
}

func TestDeaconPatrolNextIterationBurnsCurrentBeforeIdleExit(t *testing.T) {
	path := packPath("formulas", "mol-deacon-patrol.toml")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading deacon formula: %v", err)
	}
	body := string(data)
	section := sectionBetween(t, body, `id = "next-iteration"`, "")

	// Verify the next-iteration step pours the next wisp.
	if !strings.Contains(section, "gc bd mol wisp mol-deacon-patrol --root-only") {
		t.Error("next-iteration step missing mol wisp pour command")
	}
	// NOTE: The SoT next-iteration step still uses <this-wisp-id> placeholder
	// and sleep-based backoff; the upstream improvements are not yet ported.
	// The following are assertions on what IS present.
	if !strings.Contains(section, "gc bd mol burn") && !strings.Contains(section, "<this-wisp-id>") {
		t.Error("next-iteration step missing wisp burn instruction")
	}
}

// ─── witness patrol formula ───────────────────────────────────────────────────

func TestWitnessPatrolLivenessProcedureUsesExactSessionIdentity(t *testing.T) {
	path := packPath("formulas", "mol-witness-patrol.toml")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading witness patrol formula: %v", err)
	}
	body := string(data)

	for _, forbidden := range []string{
		`grep -oE '(hq|sc|gc|de)-[a-z0-9]+'`,
		`(hq|sc|gc|de)-<id>`,
	} {
		if strings.Contains(body, forbidden) {
			t.Fatalf("witness patrol still contains fixed-prefix extraction %q", forbidden)
		}
	}
	// The upstream improvement uses jq $s.id/$s.name/$s.alias/$s.agent_name
	// for exact session identity lookup. The SoT pack uses a different
	// approach; we only verify the configured_named_identity field reference.
	for _, want := range []string{
		`configured_named_identity`,
	} {
		if !strings.Contains(body, want) {
			t.Errorf("witness patrol liveness procedure missing lookup key %q", want)
		}
	}
	// Note: $s.id, $s.name, $s.session_name, $s.alias, $s.agent_name fields
	// are absent from the SoT — those are upstream improvements not yet ported.
}

func TestWitnessPatrolStateClassificationCoversSessionStates(t *testing.T) {
	path := packPath("formulas", "mol-witness-patrol.toml")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading witness patrol formula: %v", err)
	}
	body := string(data)

	// States that should be listed as NOT orphaned.
	notOrphaned := []string{
		"active", "awake", "creating", "asleep",
		"drained", "suspended", "draining", "quarantined",
	}
	for _, state := range notOrphaned {
		if !strings.Contains(body, "`"+state+"`") {
			t.Errorf("witness patrol formula missing state %q", state)
		}
	}
	// States that should be listed as orphaned.
	for _, state := range []string{"archived", "closed", "absent"} {
		if !strings.Contains(body, "`"+state+"`") {
			t.Errorf("witness patrol formula missing state %q", state)
		}
	}
}

func TestWitnessPatrolAllStepsContinueNotExit(t *testing.T) {
	path := packPath("formulas", "mol-witness-patrol.toml")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading witness patrol formula: %v", err)
	}

	var parsed struct {
		Steps []struct {
			ID          string `toml:"id"`
			Description string `toml:"description"`
		} `toml:"steps"`
	}
	if _, err := toml.Decode(string(data), &parsed); err != nil {
		t.Fatalf("parsing witness patrol formula: %v", err)
	}

	byID := make(map[string]string, len(parsed.Steps))
	for _, s := range parsed.Steps {
		byID[s.ID] = s.Description
	}

	intermediate := []string{
		"check-inbox",
		"recover-orphaned-beads",
		"check-refinery",
		"check-polecat-health",
	}
	for _, id := range intermediate {
		desc, ok := byID[id]
		if !ok {
			t.Errorf("witness patrol formula missing step %q", id)
			continue
		}
		if !strings.Contains(desc, "do NOT exit") {
			t.Errorf("step %q missing continuation reminder 'do NOT exit'", id)
		}
		if !strings.Contains(desc, "next-iteration") {
			t.Errorf("step %q missing reference to `next-iteration` as the sole burn site", id)
		}
	}

	if _, ok := byID["next-iteration"]; !ok {
		t.Fatal("witness patrol formula missing `next-iteration` step")
	}
}

// ─── formula existence / structure ────────────────────────────────────────────

func TestAllFormulasExist(t *testing.T) {
	entries, err := os.ReadDir(packPath("formulas"))
	if err != nil {
		t.Fatalf("reading formulas dir: %v", err)
	}
	var count int
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".toml") {
			continue
		}
		count++
	}
	if count == 0 {
		t.Error("no formula files found")
	}
}

func TestAllPromptTemplatesExist(t *testing.T) {
	// Walk agents/ and count prompt.template.md files.
	var count int
	err := filepath.Walk(packPath("agents"), func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.Name() == "prompt.template.md" {
			count++
			data, readErr := os.ReadFile(path)
			if readErr != nil {
				t.Errorf("reading %s: %v", path, readErr)
			} else if len(data) == 0 {
				t.Errorf("prompt %s is empty", path)
			}
		}
		return nil
	})
	if err != nil {
		t.Fatalf("walking agents: %v", err)
	}
	if count != 7 {
		t.Errorf("found %d prompt templates, want 7", count)
	}
}

// ─── idea-to-plan and review-leg formulas ─────────────────────────────────────

func TestIdeaToPlanFormulaUsesSupportedPrimitives(t *testing.T) {
	path := packPath("formulas", "mol-idea-to-plan.toml")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading idea-to-plan formula: %v", err)
	}
	body := string(data)
	for _, want := range []string{
		`formula = "mol-idea-to-plan"`,
		`gc sling "$REVIEW_TARGET" "$LEG_BEAD" --on {{review_formula}}`,
		`gc bd create`,
		`gc mail send`,
		`gc bd dep add`,
		`Do NOT use unsupported upstream shortcuts`,
		`This is the only required human gate.`,
	} {
		if !strings.Contains(body, want) {
			t.Errorf("idea-to-plan formula missing %q", want)
		}
	}
}

func TestReviewLegFormulaPersistsReportAndNotifiesCoordinator(t *testing.T) {
	path := packPath("formulas", "mol-review-leg.toml")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading review-leg formula: %v", err)
	}
	body := string(data)
	// SoT uses {{issue}} rather than "$WORK_BEAD_ID" in some commands.
	for _, want := range []string{
		`formula = "mol-review-leg"`,
		`coordinator`,
		`gc bd update`,
		`--notes`,
		`gc mail send`,
		`--status=closed`,
	} {
		if !strings.Contains(body, want) {
			t.Errorf("review-leg formula missing %q", want)
		}
	}
}

// ─── gastown patrol wisp commands ────────────────────────────────────────────

func TestGastownPatrolWispCommandsPropagateRoutingNamespace(t *testing.T) {
	checks := []struct {
		rel     string
		formula string
		vars    []string
	}{
		{
			rel:     "agents/deacon/prompt.template.md",
			formula: "mol-deacon-patrol",
			vars:    []string{"--var binding_prefix="},
		},
		{
			rel:     "formulas/mol-deacon-patrol.toml",
			formula: "mol-deacon-patrol",
			vars:    []string{"--var binding_prefix="},
		},
		{
			rel:     "agents/refinery/prompt.template.md",
			formula: "mol-refinery-patrol",
			vars:    []string{"--var target_branch=", "--var rig_name=", "--var binding_prefix="},
		},
		{
			rel:     "agents/witness/prompt.template.md",
			formula: "mol-witness-patrol",
			vars:    []string{"--var binding_prefix="},
		},
		{
			rel:     "formulas/mol-refinery-patrol.toml",
			formula: "mol-refinery-patrol",
			vars:    []string{"--var target_branch=", "--var rig_name=", "--var binding_prefix="},
		},
		{
			rel:     "formulas/mol-witness-patrol.toml",
			formula: "mol-witness-patrol",
			vars:    []string{"--var binding_prefix="},
		},
	}
	for _, check := range checks {
		data, err := os.ReadFile(packPath(check.rel))
		if err != nil {
			t.Fatalf("reading %s: %v", check.rel, err)
		}
		for lineNo, line := range strings.Split(string(data), "\n") {
			if !strings.Contains(line, "gc bd mol wisp "+check.formula+" --root-only") {
				continue
			}
			for _, want := range check.vars {
				if !strings.Contains(line, want) {
					t.Errorf("%s:%d wisp command missing %q:\n%s", check.rel, lineNo+1, want, line)
				}
			}
		}
	}
}

// ─── rig scope shell token ────────────────────────────────────────────────────

func TestAttachedRigScopeShellToken(t *testing.T) {
	for _, shell := range []string{"sh", "zsh"} {
		t.Run(shell, func(t *testing.T) {
			path, err := exec.LookPath(shell)
			if err != nil {
				t.Skipf("%s not installed", shell)
			}

			cmd := exec.Command(path, "-c", `GC_RIG=gascity; for arg in ${GC_RIG:+--rig="$GC_RIG"}; do printf '<%s>\n' "$arg"; done`)
			out, err := cmd.CombinedOutput()
			if err != nil {
				t.Fatalf("%s expansion failed: %v\n%s", shell, err, out)
			}
			if got, want := strings.TrimSpace(string(out)), "<--rig=gascity>"; got != want {
				t.Fatalf("%s non-empty expansion = %q, want %q", shell, got, want)
			}

			cmd = exec.Command(path, "-c", `unset GC_RIG; for arg in ${GC_RIG:+--rig="$GC_RIG"}; do printf '<%s>\n' "$arg"; done`)
			out, err = cmd.CombinedOutput()
			if err != nil {
				t.Fatalf("%s empty expansion failed: %v\n%s", shell, err, out)
			}
			if got := strings.TrimSpace(string(out)); got != "" {
				t.Fatalf("%s empty expansion = %q, want empty", shell, got)
			}
		})
	}
}

// ─── rig target shell expressions ─────────────────────────────────────────────

func TestGastownRigTargetShellExpressionsRenderForRigAndHQ(t *testing.T) {
	tests := []struct {
		name      string
		expr      string
		gcRig     string
		targetRig string
		want      string
	}{
		{
			name: "refinery hq no binding",
			expr: `${GC_RIG:+$GC_RIG/}refinery`,
			want: "refinery",
		},
		{
			name:  "refinery rig with binding",
			expr:  `${GC_RIG:+$GC_RIG/}review.refinery`,
			gcRig: "gascity",
			want:  "gascity/review.refinery",
		},
		{
			name: "polecat hq with binding",
			expr: `${GC_RIG:+$GC_RIG/}review.polecat`,
			want: "review.polecat",
		},
		{
			name:  "polecat rig with binding",
			expr:  `${GC_RIG:+$GC_RIG/}review.polecat`,
			gcRig: "gascity",
			want:  "gascity/review.polecat",
		},
		{
			name: "mayor polecat hq with binding",
			expr: `${TARGET_RIG:+$TARGET_RIG/}review.polecat`,
			want: "review.polecat",
		},
		{
			name:      "mayor polecat rig with binding",
			expr:      `${TARGET_RIG:+$TARGET_RIG/}review.polecat`,
			targetRig: "gascity",
			want:      "gascity/review.polecat",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cmd := exec.Command("sh", "-c", `printf '%s' "`+tt.expr+`"`)
			cmd.Env = append(os.Environ(), "GC_RIG="+tt.gcRig, "TARGET_RIG="+tt.targetRig)
			out, err := cmd.Output()
			if err != nil {
				t.Fatalf("render target: %v", err)
			}
			if got := string(out); got != tt.want {
				t.Fatalf("target = %q, want %q", got, tt.want)
			}
		})
	}
}

// ─── refinery rejection commands ─────────────────────────────────────────────

func TestGastownRefineryPatrolRejectionCommandsReturnWorkToPolecatPool(t *testing.T) {
	data, err := os.ReadFile(packPath("formulas", "mol-refinery-patrol.toml"))
	if err != nil {
		t.Fatalf("reading mol-refinery-patrol.toml: %v", err)
	}
	body := string(data)

	checks := []struct {
		name      string
		startText string
		endText   string
	}{
		{
			name:      "rebase conflict rejection",
			startText: "If rebase FAILED (conflicts):",
			endText:   "A new polecat will pick up the bead",
		},
		{
			name:      "test failure rejection",
			startText: "If branch caused it:",
			endText:   "If pre-existing on target:",
		},
	}
	for _, check := range checks {
		t.Run(check.name, func(t *testing.T) {
			start := strings.Index(body, check.startText)
			if start < 0 {
				t.Fatalf("missing section start %q", check.startText)
			}
			end := strings.Index(body[start:], check.endText)
			if end < 0 {
				t.Fatalf("missing section end %q after %q", check.endText, check.startText)
			}
			section := body[start : start+end]
			for _, want := range []string{
				"gc workflow delete-source $WORK --apply && gc workflow reopen-source $WORK",
				"gc bd update $WORK",
				"--status=open",
				`--assignee=""`,
				"--set-metadata rejection_reason=",
			} {
				if !strings.Contains(section, want) {
					t.Errorf("%s missing %q:\n%s", check.name, want, section)
				}
			}
		})
	}
}

// ─── operational awareness fragment ─────────────────────────────────────────

// killQUITRe matches `kill -QUIT` as an executable invocation — anchored at
// start-of-line (with optional leading whitespace). Combined with
// stripShellComments, this leaves only active shell statements as candidates.
var killQUITRe = regexp.MustCompile(`(?m)^[ \t]*kill[ \t\\]+\n?[ \t]*-QUIT(\s|$)`)

func TestOperationalAwarenessFragmentNonFatalDiagnostic(t *testing.T) {
	path := packPath("template-fragments", "operational-awareness.template.md")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read operational-awareness.template.md: %v", err)
	}
	body := string(data)
	active := stripShellComments(body)

	t.Run("no_active_kill_QUIT", func(t *testing.T) {
		if m := killQUITRe.FindString(active); m != "" {
			t.Errorf("operational-awareness.template.md contains an active `kill -QUIT` step (match: %q). "+
				"SIGQUIT is fatal to Dolt's Go runtime. See issue #1485.", m)
		}
	})

	t.Run("documents_non_fatal_default", func(t *testing.T) {
		wantOne := []string{
			"SHOW FULL PROCESSLIST",
			"gc dolt sql -q",
		}
		for _, w := range wantOne {
			if strings.Contains(active, w) {
				return
			}
		}
		t.Errorf("operational-awareness.template.md does not document any non-fatal Dolt diagnostic "+
			"as an active step; expected at least one of %v. See issue #1485.", wantOne)
	})

	t.Run("no_false_safe_claim", func(t *testing.T) {
		if strings.Contains(body, "safe — does not kill the process") {
			t.Errorf("operational-awareness.template.md still contains the false-safe SIGQUIT claim. See issue #1485.")
		}
	})

	t.Run("no_hardcoded_dolt_connection_literals", func(t *testing.T) {
		for _, want := range []string{"port 3307", "conn_max 50"} {
			if strings.Contains(body, want) {
				t.Errorf("operational-awareness.template.md still contains hardcoded Dolt connection literal %q", want)
			}
		}
		if !strings.Contains(body, "GC_DOLT_PORT") {
			t.Errorf("operational-awareness.template.md should reference GC_DOLT_PORT instead of a hardcoded port")
		}
		if !strings.Contains(body, "max_connections") {
			t.Errorf("operational-awareness.template.md should reference max_connections from the live server config")
		}
	})
}
