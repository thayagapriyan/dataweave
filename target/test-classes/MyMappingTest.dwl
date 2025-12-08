%dw 2.9
import * from dw::test::Tests
import * from dw::test::Asserts
---
"Test MyMapping" describedBy [
    "Assert success" in do {
        evalPath("MyMapping.dwl", inputsFrom("MyMapping/success/inputs/payload.json"),"application/json") must
                  equalTo(outputFrom("MyMapping/success/out.json"))
    }
]
