# Changelog

## 0.5.0

- A tool's name is a `ToolName` from is_model_vocabulary, in both
  `ToolSpec.name` and `OneActionTool.name`: 1 to 64 of `a-zA-Z0-9_-`, the
  rule the Messages API and the Responses API impose. Make one with
  `ToolName.of('issue_close')`. `OneActionTool.of` no longer throws for an
  empty name, since a `ToolName` can't be one, and `OneActionTool.parse`
  refuses a name that breaks the rule.
- `ToolSpec.offered` and `OneActionTool.offered` give the `OfferedTool`
  the model is shown: name, description and input schema, built from the
  definition so the two can't differ.
- Re-exports `ToolName` and `OfferedTool`. Depends on is_model_vocabulary,
  which the dependency test now admits by name.
- Depends on is_web_address_vocabulary ^0.1.2, whose `WebPath.parse('')`
  gives `WebPath.root`, so `OneActionTool.parse` reads a fetch of an
  origin's root with no special case of its own. The wire is unchanged.

## 0.4.0

- `OneActionTool`'s action is a `ToolAction`, a closed set of what a tool
  may propose, instead of a free-text `ActionName`. Its one case, `Fetch`,
  holds an `Origin` and `WebPath` from is_web_address_vocabulary and a
  `SignIn` from is_sign_in_vocabulary, all fixed when the tool is made. On
  the wire: `["propose", "fetch", <origin>, <path>, <sign-in>]`.
- Removed from `OneActionTool`, since no stage-1 tool uses them: `bound`,
  `arguments`, `argumentsFor`, `ActionArgument`, `BoundReference`,
  `InputReference`, `Literal` and `ActionName`. A tool's JSON has no
  `bound` key, and `parse` refuses one that does. Also removed:
  `Input.namesAlwaysReadAsStringIntegerOrBoolean`, which only they used.
- Re-exports `Origin`, `WebPath` and `SignIn`, which `Fetch` takes.
- Depends on is_web_address_vocabulary and is_sign_in_vocabulary, and on
  nothing else of intersyntactic's but checked_json. A test walks pub's
  resolved graph and fails if anything needed at run time is not one of
  those, named one by one.

## 0.3.0

- `Input.parse` reads back the JSON Schema that `Input.schema` writes, as an
  `Input<JsonObject>` that accepts and refuses what the writer's `Input` does
  and names the same field when it refuses. It reads a call as JSON: a
  default in place of an absent field, and nothing for an absent optional
  one. Any schema an `Input` does not write gives null.
- `Field.orDefault` throws an `ArgumentError` for a default its own schema
  refuses, such as `0` for `Schema.integer(minimum: 1)`.
- `OneActionTool`: a tool sent as data whose steps are one proposed action
  (stage 1 of agent_loop's tools-as-data design). It holds a name,
  description, input, `bound` values and the `ActionName` it proposes with
  its arguments, each a `BoundReference`, an `InputReference` or a
  `Literal`. `parse` reads the JSON `toJson` writes and gives null for
  anything else, including an input reference to a field that is optional
  or that holds a number, list or object. `argumentsFor` fills in one call's
  arguments, and refuses a call whose referenced value is no literal, such
  as a string over 64 KiB.
- `Input.namesAlwaysReadAsStringIntegerOrBoolean`: the fields every read
  gives a string, whole number or boolean for.

## 0.2.1

- Exports checked_json's `JsonObject` and `JsonFieldException`, and nothing
  else of it: `Input.read` takes the one and throws the other, and
  `ToolSpec.toJson` returns a `JsonObject`, so a package that depends on this
  one alone can name them.
- The package description says what 0.2.0 holds: a tool's input and output,
  and the types of what a call takes and returns.

## 0.2.0

- `ToolSpec<I, O>` is a tool's definition only: its name, description,
  `input` and `concurrent`, and the types of what a call takes, `I`, and
  returns, `O`. `ToolSpec.run`, `ToolContext`, `ToolImage` and
  `ToolProcessTap` are removed: the code that answers a call, and what a call
  reports while it runs, belong to the airlock, which attaches it through the
  definition so that it must take an `I` and return an `O`.
- `Input<I>`, `Field<T>` and `Schema<T>` replace the hand-written
  `inputSchema` map: one description gives both the JSON Schema the model is
  shown and the reader that turns what it sent into an `I`, with every
  constraint the schema shows checked by the reader. `inputSchema` is now
  `input.schema`.
- `Output<O>` turns the `O` a call returns into the text of its tool result,
  once per tool; `Output.text` is for an answer that is already text. A
  failed call has no `O`: whoever runs the call reports it.
- The library comment says kit for a host's set of tools.

## 0.1.0

- First release: `ToolSpec`, `ToolContext`, `ToolImage` and `ToolProcessTap`,
  the contract intersyntactic's tools are written against.
