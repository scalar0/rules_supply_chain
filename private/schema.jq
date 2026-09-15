.[0] as $base
| reduce .[1:][] as $extension ($base;
    if ($extension["$defs"] | type) != "object" then error("Invalid schema definitions") else . end
    | .["$defs"] as $existing
    | if any($extension["$defs"] | keys[]; . as $key | $existing | has($key))
      then error("Duplicate schema definition") else . end
    | .["$defs"] += $extension["$defs"])
