%dw 2.9
output application/json

import * from MyModule
---
{
    name: "Hello world!",
    result: add(5, 10)
}