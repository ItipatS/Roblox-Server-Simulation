```lua
type Todo = {
    text: string,
    done: () -> boolean
}

local todos = source {} :: () -> Array<Todo>

values(todos, function(todo, i)
    return create "TextButton" {
        Text = function()
            return todo.done() and "[x]" or "[ ]" .. todo.text
        end,

        Activated = function()
            todo.done(not todo.done())
        end

        LayoutOrder = i
    }
end)

local function add_todo(text: string)
    local data = todos()
    table.insert(data, { text = text, done = source(false) })
    todos(data)
end
```

```lua
type Todo = {
    text: string,
    done: boolean
}

local todos = list({} :: Array<Todo>)

values(todos.get, function(todo, i)
    return create "TextButton" {
        Text = function()
            return todo.done and "[x]" or "[ ]" .. todo.text
        end,

        Activated = function()
            todo.done = not todo.done
        end

        LayoutOrder = i
    }
end)

local function add_todo(text: string)
    todos.push { text = text, done = false }
end
```





