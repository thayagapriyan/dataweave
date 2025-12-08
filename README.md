# dataweave

Small DataWeave library + tests used for examples and local testing.

https://docs.mulesoft.com/dataweave/latest/dataweave-extension-plugin#test-a-dataweave-mapping

**Project layout**
- `src/main/dw/` — DataWeave modules (shared functions)
- `src/test/dw/` — DataWeave test mappings/tests
- `src/test/resources/` — Test input/output fixtures
- `pom.xml` — Maven build and DataWeave plugin configuration

**Prerequisites**
- Java JDK (11+) installed and `JAVA_HOME` set.
- Maven installed and available as `mvn` on your PATH.

If `mvn` is not found on Windows PowerShell you will see: `'mvn' is not recognized`.
Install Maven and restart the shell.

Quick start — run tests

PowerShell:
```powershell
cd 'c:\Priyan\VSC\DATAWEAVE\dataweave'
mvn test
```

Run a single mapping (manual test)
- You can run/test single `.dwl` files in an integration environment or use the DataWeave testing framework via `mvn test`.

Common issues & troubleshooting
- Parsing errors: ensure test files do NOT contain Markdown fences like ```data-weave. Tests must be plain `.dwl` files starting with `%dw`.
- Version mismatch: tests in this repo use DataWeave test helpers that may expect `%dw 2.0` syntax. If you see `describedBy` parse errors try switching to the `%dw` version matching your test harness or convert tests to the newer test DSL.
- Import mismatches: `import helloWorld from MyModule` requires a `MyModule.dwl` that exports that symbol. Module and import names are case-sensitive.
- Network/plugin issues: Maven may fail to download dependencies/plugins if your network or repository settings block `repository-master.mulesoft.org`. Configure Maven `settings.xml` or proxy as needed.

If you want, I can:
- Run `mvn test` here (I previously couldn't because `mvn` wasn't available).
- Convert tests to the newer DataWeave test DSL.

Contact / next steps
- Tell me whether to run the tests locally (if you install Maven) or to convert tests to the newer syntax and I will update the files.
