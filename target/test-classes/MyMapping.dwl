/**
 * This mapping won't be shared through your library, but you can use it to try out your module and create integration tests.
 */
%dw 2.9
output application/json

import * from MyModule
---
add(1, 2)