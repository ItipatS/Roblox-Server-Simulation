local jecs = require(game:GetService("ReplicatedStorage").ecs)
local world = require(script.Parent.world)

type Entity<T = nil> = jecs.Entity<T>
local components: {
	Character: Entity<Model>,
	Mob: Entity,
	Model: Entity<Model>,
	Player: Entity,
	Target: Entity,
	Transform: Entity<{ new: CFrame, old: CFrame }>,
	Velocity: Entity<number>,
	Previous: Entity,
	Size: Entity<number>,

	PendingMovements: Entity<{ [number]:{ id:number, dp: Vector3 } }>,
	PendingStates: Entity<{ [number]:{ id:number, isFleeing: boolean, fleeTimer: number } }>,

	Dust: Entity, -- tag
    DustData: Entity<{
        rarity: string
    }>,
    DustState: Entity<{
        isFleeing: boolean,
        fleeTimer: number,
    }>,
    DustDrag: Entity<{
        draggerUserId: number?,
        targetPos: Vector3?, 
    }>,
} = {
		Character = world:component(),
		Mob = world:component(),
		Model = world:component(),
		Player = world:component(),
		Target = world:component(),
		Transform = world:component(),
		Velocity = world:component(),
		Previous = world:component(),
		Size = world:component(),

		PendingMovements = world:component(),
		PendingStates = world:component(),

		Dust = world:component(),
		DustData = world:component(),
		DustState = world:component(),
		DustDrag = world:component(),
	}

for name, component in components :: {[string]: jecs.Entity} do 
	world:set(component, jecs.Name, name)
end

return table.freeze(components)
