local sync = {script_data = {}, merging = false}

function get_team_map()
	local team_map = {}
	for k, team in pairs (sync.script_data.config.teams) do
			team_map[team.name] = team
	end
	return team_map
end

function get_team_number(team)
	local team_number
	if tonumber(team.team) then
			team_number = team.team
	elseif team.team:find("?") then
			team_number = team.team:gsub("?", "")
			team_number = tonumber(team_number)
	else
			team_number = nil
	end
	return team_number
end

function get_team(force)
	if not force or not force.valid then return end
	local team_map = get_team_map()
	local team = team_map[force.name]
	if not team then return end
	local team_number = get_team_number(team)
	return team, team_number
end

function for_allies(force, team_number, callback)
	for k, other_team in pairs (sync.script_data.config.teams) do
		local other_force = game.forces[other_team.name]
		if other_force and not (other_force == force) and not (other_force.name == force.name) then --ignore own force
			local other_number = get_team_number(other_team)
			if other_number == team_number then
				callback(other_force)
			end
		end
	end
end

sync.start_shared_research = function(event)
	if sync.merging then return end
	--if not sync.script_data.config.team_config then return end
	--if not sync.script_data.config.team_config.share_tech then return end

	if not sync.script_data.active_research then sync.script_data.active_research = {} end

	local force = event.research.force
	local team, team_number = get_team(force)
	--no team -> no shared research!
	if not team_number then return end

	if not sync.script_data.active_research[team_number] or sync.script_data.active_research[team_number].name ~= event.research.name then
			--enforce research
			sync.script_data.active_research[team_number] = {
				name = event.research.name,
				level = event.research.level,
				initiator = event.research.force.name,
				sync_progress = 0
			}

			if sync.script_data.research_progress[team_number] and sync.script_data.research_progress[team_number][event.research.name] then
				--local progress
				force.research_progress = sync.script_data.research_progress[team_number][event.research.name]
				sync.script_data.active_research[team_number].sync_progress = force.research_progress
			end

			--force.current_research = event.research.name
	elseif sync.script_data.active_research[team_number].name == event.research.name then
		if sync.script_data.research_progress[team_number] and sync.script_data.research_progress[team_number][event.research.name] then
			force.research_progress = sync.script_data.research_progress[team_number][event.research.name]
		end
		return --already up to date
	end

	--for all allies share research
	for_allies(force, team_number, function(other_force)
		other_force.current_research = sync.script_data.active_research[team_number].name
		if event.research.research_unit_count_formula then
			--sync level
			other_force.current_research.level = event.research.level
		end

		if sync.script_data.research_progress[team_number] and sync.script_data.research_progress[team_number][event.research.name] then
			other_force.research_progress = sync.script_data.research_progress[team_number][event.research.name]
		end
		
	end)
end

sync.finish_shared_research = function(event)
	if sync.merging then return end
	--if not sync.script_data.config.team_config then return end
	--if not sync.script_data.config.team_config.share_tech then return end
	if event.by_script then return end --skip self

	if not sync.script_data.active_research then sync.script_data.active_research = {} end

	local force = event.research.force
	local team, team_number = get_team(force)

	if not sync.script_data.active_research[team_number] then return end
	for_allies(force, team_number, function(other_force)
		other_force.technologies[sync.script_data.active_research[team_number].name].researched = event.research.researched
		if event.research.research_unit_count_formula then
		other_force.technologies[sync.script_data.active_research[team_number].name].level = event.research.level
		end
	end)
	sync.script_data.active_research[team_number] = nil
	
	if sync.script_data.research_progress[team_number] and sync.script_data.research_progress[team_number][event.research.name] then
		sync.script_data.research_progress[team_number][event.research.name] = nil --clear stored process
	end
end

--called on first init
sync.init = function()
	sync.script_data.active_research = {}
	sync.script_data.research_progress = {}
end

--called every tick
sync.check_sync = function()
	if not sync.script_data.active_research then sync.script_data.active_research = {} end
	if not sync.script_data.research_progress then sync.script_data.research_progress = {} end

	for index, force in pairs(game.forces) do
		local team, team_number = get_team(force)
		if not force.current_research and team_number and sync.script_data.active_research[team_number] then
			--someone canceled the research
			for_allies(force, team_number, function(other_force)
				other_force.current_research = nil
			end)
			if sync.script_data.research_progress[team_number] and sync.script_data.research_progress[team_number][sync.script_data.active_research[team_number].name] then
				sync.script_data.research_progress[team_number][sync.script_data.active_research[team_number].name] = nil --clear stored process
			end
			sync.script_data.active_research[team_number] = nil
		elseif force.current_research and force.current_research.researched then
			force.current_research = nil --bug
		end
	end
	for team_number, active_research in pairs(sync.script_data.active_research) do
		local team_progress = 0
		local master_force = game.forces[active_research.initiator]
		if master_force then
			for_allies(master_force, team_number, function(other_force)
				if other_force.current_research then
					--accumulate progress
				team_progress = team_progress + (other_force.research_progress - active_research.sync_progress)
				end
			end)
			--cap progress
			if master_force.current_research then
				team_progress = math.max(0.0, math.min(1.0, team_progress + master_force.research_progress))
				--set own progress
				master_force.research_progress = team_progress
			else
				team_progress = math.max(0.0, math.min(1.0, team_progress + active_research.sync_progress))
			end

			for_allies(master_force, team_number, function(other_force)
				if other_force.current_research then
					--set other progress
					other_force.research_progress = team_progress
				end
			end)

			active_research.sync_progress = team_progress
		end    
	end

end

--called on round end
sync.cleanup = function()
	sync.script_data.active_research = {}
	sync.script_data.research_progress = {}
end

sync.merge_tech = function()
	sync.merging = true
	if not sync.script_data.research_progress then sync.script_data.research_progress = {} end
	local forces_by_team = {}
	for index, force in pairs(game.forces) do
		local team, team_number = get_team(force)
		if team_number then
			force.current_research = nil --clear current research
			if not forces_by_team[team_number] then forces_by_team[team_number] = {forces = {}, force_count = 0} end
			forces_by_team[team_number].forces[index] = force
			forces_by_team[team_number].force_count = forces_by_team[team_number].force_count + 1
		end
	end

	for team_number, forces in pairs(forces_by_team) do
		forces.tech = {}
		for index, force in pairs(forces.forces) do
			for tech_name, technology in pairs(force.technologies) do
				if technology.researched then
					if not forces.tech[tech_name] then forces.tech[tech_name] = 0 end
					forces.tech[tech_name] = forces.tech[tech_name] + 1
				end
			end
			--force.laboratory_productivity_bonus = -(1.0  - ( 1.0 / (forces.force_count)))
			game.difficulty_settings.technology_price_multiplier = forces.force_count - 2
		end
	end

	for team_number, forces in pairs(forces_by_team) do
		for index, force in pairs(forces.forces) do
			for tech_name, technology in pairs(force.technologies) do
				if forces.tech[tech_name] and forces.tech[tech_name] >= forces.force_count then
					technology.researched = true
				else
					technology.researched = false
				end
			end
		end
	end

	for team_number, forces in pairs(forces_by_team) do
		for tech_name, amount in pairs(forces.tech) do
			if forces.tech[tech_name] <= 0 then
				forces.tech[tech_name] = nil
			else
				forces.tech[tech_name] = 1 - (1.0 / forces.tech[tech_name])
			end
		end
		sync.script_data.research_progress[team_number] = math.max(0, math.min(forces.tech, 1))
	end
	sync.merging = false
end

return sync
