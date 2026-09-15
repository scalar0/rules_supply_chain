$ARGS.named as $args
| range(0; ($args | length) / 3) | tostring as $index
| {
    key: $args["path_" + $index],
    value: ($args["text_" + $index] |
      if $args["kind_" + $index] == "metadata" then fromjson else . end)
  }
