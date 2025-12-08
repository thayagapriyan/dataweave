%dw 2.9
output application/json

import * from MyModule
---
{
    result: add(5, 10)
}