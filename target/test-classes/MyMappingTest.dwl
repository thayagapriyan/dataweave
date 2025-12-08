%dw 2.9
import * from dw::test::Tests
import * from dw::test::Asserts
---
"Test MyMapping" describedBy [
    "Assert success" in do {
        evalPath("MyMapping.dwl", inputsFrom("MyMapping/success"),"application/json") must
                  equalTo(outputFrom("MyMapping/success"))
    }
]
