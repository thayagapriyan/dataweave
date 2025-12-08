%dw 2.0
import * from dw::test::Tests
import * from dw::test::Asserts

import * from MyModule
---
"MyModule" describedBy [
    "add" describedBy [
        "It should do something" in do {
            add(1, 2) must beNumber()
        },
    ],
]
