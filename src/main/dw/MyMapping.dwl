%dw 2.9
output application/json

import * from MyModule
---
{
    name: payload.name,
    result: add(5, 10)
}