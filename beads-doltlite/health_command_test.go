package beadsdoltlite_test

import (
	"bytes"
	"encoding/json"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	beadsdoltlite "github.com/gastownhall/gascity-packs/beads-doltlite"
)

func TestDoltliteHealthScriptDoesNotForceDefaultShellTimeout(t *testing.T) {
	script := filepath.Join(repoRootForTest(t), "commands", "health", "run.sh")
	text := mustReadFile(t, script)
	if strings.Contains(string(text), "\"${GC_DOLTLITE_HEALTH_TIMEOUT:-15s}\"") {
		t.Fatalf("health run script still hardcodes a 15s timeout default")
	}
}

func TestDoltliteBuildScriptBuildsGCWithNativeReadTag(t *testing.T) {
	script := filepath.Join(repoRootForTest(t), "commands", "build", "run.sh")
	text := string(mustReadFile(t, script))

	for _, required := range []string{
		`common_env_prefix "gascity_doltlite_lib,libsqlite3"`,
		`ensure_gc_release_binary`,
		`default_gc_release_version`,
		`latest_gc_release_version`,
		`https://api.github.com/repos/duncan4123/gascity/releases`,
		`^v\d+\.\d+\.\d+-doltlite\.workflow\.\d+$`,
		`version="$(default_gc_release_version)" || return $?`,
		`version="$(basename "$(dirname "$(dirname "$release_bin")")")"`,
		`gascity-doltlite_${version#v}_${platform}.tar.gz`,
		`gascity_doltlite_edge_linux_amd64.tar.gz`,
		`https://github.com/duncan4123/gascity/releases/download/${version}`,
		`DoltLite-linked gc release unavailable; falling back to source build`,
		`download_file "$asset_url" "$archive_path" || return $?`,
		`verify_checksum_file "$checksum_path" "$archive_path" || return $?`,
		`extract_tar_binary "$archive_path" "$binary_name" "$bin_path" || return $?`,
		`--build-gc-from-source`,
		`GC_DOLTLITE_BUILD_GC_FROM_SOURCE`,
		`GC_DOLTLITE_GC_RELEASE_VERSION, GC_DOLTLITE_GC_RELEASE_BASE`,
		`GC_DOLTLITE_GC_RELEASE_API`,
		`binary_has_go_build_tag "$output" "gascity_doltlite_lib"`,
		`built gc binary does not report -tags including gascity_doltlite_lib`,
		`built gc binary is missing native DoltLite read-store symbols`,
		`no symbol section|no symbols`,
		`running_supervisor_gc_path`,
		`pgrep -f '(^|/)gc supervisor run($| )'`,
		`readlink "/proc/$pid/exe"`,
		`timeout 10s "$current" status --json "$CITY_ROOT"`,
		`controller_field_for_city "$current" "binary"`,
		`current="$(running_supervisor_gc_path || true)"`,
		`gc_install_paths`,
		`current="$(supervisor_gc_path || true)"`,
		`current="$(command -v gc 2>/dev/null || true)"`,
		`resolved $name install symlink`,
		`installed $name does not match built binary`,
		`"tags": "%s"`,
		`-ldoltlite -lm`,
		`-L${DOLTLITE_LIB} ${DOLTLITE_LIB}/libdoltlite.a`,
		`grep -aiq 'doltlite' "$output"`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("build script missing %q", required)
		}
	}
}

func TestDoltliteBuildHelpExplainsTargetSelection(t *testing.T) {
	root := repoRootForTest(t)
	script := string(mustReadFile(t, filepath.Join(root, "commands", "build", "run.sh")))
	help := string(mustReadFile(t, filepath.Join(root, "commands", "build", "help.md")))
	skill := string(mustReadFile(t, filepath.Join(root, "skills", "doltlite", "SKILL.md")))

	for _, required := range []string{
		`gc      Normal init path`,
		`all     Coordinated rebuild`,
		`Builds bd, doltlite-client, then gc`,
		`not skip unchanged targets`,
		`DoltLite-linked gc binary`,
		`gc beads-doltlite build gc --install --no-restart`,
	} {
		if !strings.Contains(script, required) {
			t.Fatalf("build script help missing %q", required)
		}
	}

	for _, required := range []string{
		`The default target is ` + "`gc`",
		`normal Gas City`,
		`latest released DoltLite-linked ` + "`gc`" + ` archive`,
		`--build-gc-from-source`,
		`all` + "` builds `" + `bd` + "`, `" + `doltlite-client` + "`, then `" + `gc`,
		`does not skip unchanged`,
		`pinned DoltLite release library`,
		`updates every distinct home-owned entrypoint`,
		`running supervisor binary`,
		`active controller ` + "`gc`" + ` path`,
		`Symlinks are resolved before`,
	} {
		if !strings.Contains(help, required) {
			t.Fatalf("build long help missing %q", required)
		}
	}

	for _, required := range []string{
		`install only ` + "`gc`",
		`gc beads-doltlite build gc --install --no-restart`,
		`only for coordinated`,
		`latest released DoltLite-linked Gas City archive`,
		`download pinned DoltLite and latest Gas City release artifacts`,
	} {
		if !strings.Contains(skill, required) {
			t.Fatalf("doltlite skill missing %q", required)
		}
	}
}

func TestDoltliteSqlitebrowserCommandBuildsAgainstLibdoltlite(t *testing.T) {
	root := repoRootForTest(t)
	manifest := string(mustReadFile(t, filepath.Join(root, "commands", "sqlitebrowser", "command.toml")))
	script := string(mustReadFile(t, filepath.Join(root, "commands", "sqlitebrowser", "run.sh")))
	help := string(mustReadFile(t, filepath.Join(root, "commands", "sqlitebrowser", "help.md")))
	skill := string(mustReadFile(t, filepath.Join(root, "skills", "doltlite", "SKILL.md")))

	if !strings.Contains(manifest, "DB Browser for SQLite against libdoltlite") {
		t.Fatalf("sqlitebrowser manifest missing libdoltlite description: %s", manifest)
	}
	for _, required := range []string{
		`usage: gc beads-doltlite sqlitebrowser [open|project|build|path]`,
		`-Dsqlcipher=0`,
		`-DSQLite3_INCLUDE_DIR="$DOLTLITE_LIB"`,
		`-DSQLite3_LIBRARY="$lib_file"`,
		`libdoltlite`,
		`sqlitebrowser-doltlite`,
		`DISPLAY, WAYLAND_DISPLAY, or QT_QPA_PLATFORM`,
		`--allow-network-fetch`,
		`require_pinned_ref "$SQLITEBROWSER_REF"`,
		`network fetch requires --ref`,
		`generate_browser_project`,
		`generate-formula-progress-sql.py`,
		`<tab_sql>`,
		`Formula progress`,
	} {
		if !strings.Contains(script, required) {
			t.Fatalf("sqlitebrowser script missing %q", required)
		}
	}
	for _, required := range []string{
		`stock SQLite or SQLCipher`,
		`CMake's SQLite dependency at ` + "`libdoltlite`",
		`gc beads-doltlite sqlitebrowser build`,
		`Network fetches are explicit`,
		`gc beads-doltlite sqlitebrowser project --city`,
		`gc beads-doltlite sqlitebrowser open --db`,
		`loads a formula-progress SQL tab`,
	} {
		if !strings.Contains(help, required) {
			t.Fatalf("sqlitebrowser help missing %q", required)
		}
	}
	for _, required := range []string{
		`gc beads-doltlite sqlitebrowser build/open`,
		`stock SQLite Browser builds cannot open DoltLite-format databases`,
		`open --city <city>`,
	} {
		if !strings.Contains(skill, required) {
			t.Fatalf("doltlite skill missing %q", required)
		}
	}
}

func TestDoltliteSqlitebrowserPathUsesCityMetadata(t *testing.T) {
	root := repoRootForTest(t)
	city := t.TempDir()
	lib := filepath.Join(city, "doltlite-work", "build")
	dbDir := filepath.Join(city, ".beads", "doltlite")
	if err := os.MkdirAll(lib, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(dbDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(lib, "libdoltlite.so"), []byte("fake"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(city, ".beads", "metadata.json"), []byte(`{"backend":"doltlite","database":"doltlite","dolt_database":"hq"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	wantDB := filepath.Join(dbDir, "hq.db")
	if err := os.WriteFile(wantDB, []byte("fake"), 0o644); err != nil {
		t.Fatal(err)
	}

	cmd := exec.Command("bash", filepath.Join(root, "commands", "sqlitebrowser", "run.sh"), "path", "--city", city, "--lib", lib)
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out
	if err := cmd.Run(); err != nil {
		t.Fatalf("sqlitebrowser path failed: %v\noutput=%s", err, out.String())
	}
	if got := strings.TrimSpace(out.String()); got != wantDB {
		t.Fatalf("sqlitebrowser path = %q, want %q", got, wantDB)
	}
}

func TestDoltliteSqlitebrowserProjectGeneratesBrowserSetup(t *testing.T) {
	root := repoRootForTest(t)
	city := t.TempDir()
	for _, dir := range []string{
		filepath.Join(city, ".beads", "doltlite"),
		filepath.Join(city, ".beads", "formulas"),
		filepath.Join(city, "rig-one", ".beads", "doltlite"),
	} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(city, ".beads", "metadata.json"), []byte(`{"backend":"doltlite","database":"doltlite","dolt_database":"hq"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	hqDB := filepath.Join(city, ".beads", "doltlite", "hq.db")
	rigDB := filepath.Join(city, "rig-one", ".beads", "doltlite", "ri.db")
	if err := os.WriteFile(hqDB, []byte("fake"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(rigDB, []byte("fake"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(city, ".beads", "formulas", "demo.toml"), []byte(`
formula = "demo"
contract = "graph.v2"

[[steps]]
id = "prepare"
title = "Prepare demo"
`), 0o644); err != nil {
		t.Fatal(err)
	}

	outDir := t.TempDir()
	projectPath := filepath.Join(outDir, "browser.sqbpro")
	sqlPath := filepath.Join(outDir, "formula-progress.sql")
	cmd := exec.Command(
		"bash",
		filepath.Join(root, "commands", "sqlitebrowser", "run.sh"),
		"project",
		"--city", city,
		"--project", projectPath,
		"--sql", sqlPath,
	)
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out
	if err := cmd.Run(); err != nil {
		t.Fatalf("sqlitebrowser project failed: %v\noutput=%s", err, out.String())
	}
	if got := strings.TrimSpace(out.String()); got != projectPath {
		t.Fatalf("project output = %q, want %q", got, projectPath)
	}

	project := string(mustReadFile(t, projectPath))
	for _, required := range []string{
		`<db path="` + hqDB + `" readonly="1"`,
		`schema="rig_ri"`,
		`path="` + rigDB + `"`,
		`<main_tabs open="structure browse pragma sql plot" current="3"/>`,
		`<sql name="Formula progress" filename="` + sqlPath + `"`,
	} {
		if !strings.Contains(project, required) {
			t.Fatalf("generated project missing %q:\n%s", required, project)
		}
	}

	sql := string(mustReadFile(t, sqlPath))
	for _, required := range []string{
		"formula_steps",
		"'demo.prepare'",
		"assumes rig databases are already attached",
	} {
		if !strings.Contains(sql, required) {
			t.Fatalf("generated SQL missing %q", required)
		}
	}
	if strings.Contains(sql, "ATTACH DATABASE") {
		t.Fatalf("generated project SQL should not include ATTACH DATABASE statements:\n%s", sql)
	}
}

func TestDoltlitePackEmbedsHQAndRigBrowserExample(t *testing.T) {
	for _, path := range []string{
		"examples/hq-rig-browser/README.md",
		"examples/hq-rig-browser/doltlite-gascity-attach.sql",
		"examples/hq-rig-browser/doltlite-gascity-hq-rigs.sqbpro",
		"examples/formula-progress/README.md",
		"examples/formula-progress/generate-formula-progress-sql.py",
		"examples/formula-progress/doltlite-gascity-formula-progress.sql",
		"examples/formula-progress/doltlite-gascity-formula-progress-no-attach.sql",
		"assets/scripts/gc-beads-doltlite-bd.sh",
	} {
		if _, err := fs.Stat(beadsdoltlite.PackFS, path); err != nil {
			t.Fatalf("embedded pack missing %s: %v", path, err)
		}
	}
	provider, err := fs.ReadFile(beadsdoltlite.PackFS, "assets/scripts/gc-beads-doltlite-bd.sh")
	if err != nil {
		t.Fatalf("reading embedded provider: %v", err)
	}
	for _, required := range []string{
		"gc-beads-bd",
		"is_doltlite_backend",
		"BEADS_BACKEND",
		`BEADS_BACKEND="${GC_BEADS_BACKEND:-${BEADS_BACKEND:-doltlite}}"`,
		"init --backend doltlite",
		`ensure_doltlite_runtime_custom_types "$dir" "$custom_types"`,
		`ensure_doltlite_runtime_issue_prefix "$dir" "$prefix"`,
	} {
		if !strings.Contains(string(provider), required) {
			t.Fatalf("embedded provider missing %q", required)
		}
	}

	sql := string(mustReadFile(t, filepath.Join(repoRootForTest(t), "examples", "hq-rig-browser", "doltlite-gascity-attach.sql")))
	project := string(mustReadFile(t, filepath.Join(repoRootForTest(t), "examples", "hq-rig-browser", "doltlite-gascity-hq-rigs.sqbpro")))
	for _, required := range []string{
		`ATTACH DATABASE '/data/projects/doltlite-gascity/beads-doltlite/.beads/doltlite/bd.db' AS rig_bd`,
		`ATTACH DATABASE '/data/projects/doltlite-gascity/gascity/.beads/doltlite/gc.db' AS rig_gc`,
		`ATTACH DATABASE '/data/projects/doltlite-gascity/gascity-packs/.beads/doltlite/gp.db' AS rig_gp`,
		`ATTACH DATABASE '/data/projects/doltlite-gascity/gascity/gascity-dashboard/.beads/doltlite/gd.db' AS rig_gd`,
		`ATTACH DATABASE '/data/projects/doltlite-gascity/lightjj/.beads/doltlite/lj.db' AS rig_lj`,
		`PRAGMA database_list`,
		`Blocked beads across HQ and rigs`,
	} {
		if !strings.Contains(sql, required) {
			t.Fatalf("hq/rig browser SQL missing %q", required)
		}
	}
	for _, required := range []string{
		`<db path="/data/projects/doltlite-gascity/.beads/doltlite/hq.db" readonly="1"`,
		`schema="rig_bd"`,
		`schema="rig_gc"`,
		`schema="rig_gp"`,
		`schema="rig_gd"`,
		`schema="rig_lj"`,
	} {
		if !strings.Contains(project, required) {
			t.Fatalf("hq/rig project missing %q", required)
		}
	}
}

func TestDoltliteFormulaProgressGeneratorEmitsStepSQL(t *testing.T) {
	python, err := exec.LookPath("python3")
	if err != nil {
		t.Skip("python3 not available")
	}
	root := repoRootForTest(t)
	formulaDir := filepath.Join(t.TempDir(), "formulas")
	if err := os.MkdirAll(formulaDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(formulaDir, "demo.toml"), []byte(`
formula = "demo"
version = 1
contract = "graph.v2"

[[steps]]
id = "prepare"
title = "Prepare demo"
metadata = { "gc.run_target" = "gc.run-operator" }

[[steps]]
id = "finish"
title = "Finish demo"
needs = ["prepare"]
`), 0o644); err != nil {
		t.Fatal(err)
	}

	output := filepath.Join(t.TempDir(), "formula-progress.sql")
	cmd := exec.Command(
		python,
		filepath.Join(root, "examples", "formula-progress", "generate-formula-progress-sql.py"),
		"--city", t.TempDir(),
		"--formula-root", formulaDir,
		"--database", "hq=main",
		"--output", output,
	)
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out
	if err := cmd.Run(); err != nil {
		t.Fatalf("formula progress generator failed: %v\noutput=%s", err, out.String())
	}

	sql := string(mustReadFile(t, output))
	for _, required := range []string{
		"formula_steps",
		"'demo.prepare'",
		"'demo.finish'",
		`json_extract(metadata, '$."gc.step_ref"')`,
		"Workflow progress rollup",
		"Runtime-generated or expansion steps",
		"session_beads_debug",
		"session_demand_debug",
		"ready-routed-no-session-bead",
	} {
		if !strings.Contains(sql, required) {
			t.Fatalf("generated formula progress SQL missing %q", required)
		}
	}

	noAttachOutput := filepath.Join(t.TempDir(), "formula-progress-no-attach.sql")
	cmd = exec.Command(
		python,
		filepath.Join(root, "examples", "formula-progress", "generate-formula-progress-sql.py"),
		"--city", t.TempDir(),
		"--formula-root", formulaDir,
		"--database", "hq=main",
		"--attach-mode", "none",
		"--output", noAttachOutput,
	)
	out.Reset()
	cmd.Stdout = &out
	cmd.Stderr = &out
	if err := cmd.Run(); err != nil {
		t.Fatalf("formula progress no-attach generator failed: %v\noutput=%s", err, out.String())
	}
	noAttachSQL := string(mustReadFile(t, noAttachOutput))
	if strings.Contains(noAttachSQL, "ATTACH DATABASE") {
		t.Fatalf("no-attach SQL should not include ATTACH DATABASE statements:\n%s", noAttachSQL)
	}
	if !strings.Contains(noAttachSQL, "assumes rig databases are already attached") {
		t.Fatalf("no-attach SQL missing already-attached note")
	}
	if !strings.Contains(noAttachSQL, "session_demand_debug") {
		t.Fatalf("no-attach SQL missing session demand debug view")
	}
}

func TestDoltliteGCLinkDoctorRequiresNativeReadBuildTag(t *testing.T) {
	script := filepath.Join(
		repoRootForTest(t),
		"doctor",
		"check-gc-doltlite-link",
		"run.sh",
	)
	text := string(mustReadFile(t, script))

	for _, required := range []string{
		`go version -m "$gc_bin"`,
		`gascity_doltlite_lib`,
		`gc binary was not built with -tags including gascity_doltlite_lib`,
		`gc beads-doltlite build gc --install`,
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("gc link doctor missing %q", required)
		}
	}
}

func TestDoltliteHealthJSONSchemaIsValidObject(t *testing.T) {
	schemaPath := filepath.Join(repoRootForTest(t), "commands", "health", "schemas", "result.schema.json")
	raw := mustReadFile(t, schemaPath)

	var parsed map[string]any
	if err := json.Unmarshal(raw, &parsed); err != nil {
		t.Fatalf("result schema is not valid JSON: %v", err)
	}
	if parsed["type"] != "object" {
		t.Fatalf("result schema should declare type=object; got %v", parsed["type"])
	}
}

func TestDoltliteHealthScriptOutputsJSONOKWithoutJq(t *testing.T) {
	script := filepath.Join(repoRootForTest(t), "commands", "health", "run.sh")
	bin := mustReadlink(t, "bd")

	cmd := exec.Command("bash", script, "--json")
	cmd.Env = append(os.Environ(),
		"GC_CITY_PATH="+filepath.Dir(repoRootForTest(t)),
		"PATH="+filepath.Dir(bin)+":"+filepath.Dir(os.Getenv("HOME"))+"/bin:"+os.Getenv("PATH"),
	)

	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out
	if err := cmd.Run(); err != nil {
		t.Fatalf("script failed: %v\noutput=%s", err, out.String())
	}
	if !strings.Contains(out.String(), "\"ok\":true") && !strings.Contains(out.String(), "\"ok\": true") {
		t.Fatalf("script output must include ok=true: %s", out.String())
	}
}

func repoRootForTest(t *testing.T) string {
	t.Helper()
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("failed to resolve test file path")
	}
	dir := filepath.Dir(filename)
	for {
		if filepath.Base(dir) == "beads-doltlite" {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			t.Fatalf("could not locate beads-doltlite root from %s", filename)
		}
		dir = parent
	}
}

func mustReadFile(t *testing.T, path string) []byte {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read file %q: %v", path, err)
	}
	return raw
}

func mustReadlink(t *testing.T, name string) string {
	t.Helper()
	path, err := exec.LookPath(name)
	if err != nil {
		t.Fatalf("look up %q: %v", name, err)
	}
	return path
}
