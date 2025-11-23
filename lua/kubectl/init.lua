local M = {}

local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
	vim.notify("Telescope is required for kubectl.nvim", vim.log.levels.ERROR)
	return
end

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local sorter = require("telescope.config").values.generic_sorter

local function notify(msg, level)
	vim.notify(msg, level, { timeout = 5000 })
end

function M.restart_pod(container_name)
	local cmd = string.format("kubectl rollout restart deployment %s", container_name)
	print("Executing command: " .. cmd)
	local result = vim.fn.system(cmd)
	if vim.v.shell_error ~= 0 then
		notify("Failed to restart pod: " .. result, vim.log.levels.ERROR)
	else
		notify("Pod " .. container_name .. " restarted.", vim.log.levels.INFO)
	end
end

local function update_image(pod_name, container_name, image, cb)
	vim.ui.input({ prompt = "New version for " .. container_name .. ": " }, function(new_version)
		if new_version and #new_version > 0 then
			local image_base = image:match("^[^:]+")
			local new_image = image_base .. ":" .. new_version
			local cmd = string.format("kubectl set image pod/%s %s=%s", pod_name, container_name, new_image)
			vim.fn.system(cmd)
			notify("Image updated: " .. cmd, vim.log.levels.INFO)
			if cb then
				cb()
			end
		end
	end)
end

function M.list_pods()
	local output = vim.fn.system("kubectl get pods -o json")
	local pods = {}
	local json = vim.fn.json_decode(output)
	for _, pod in ipairs(json.items or {}) do
		for _, container in ipairs(pod.spec.containers or {}) do
			table.insert(pods, {
				pod_name = pod.metadata.name,
				container_name = container.name,
				image = container.image,
				display = string.format("%-30s | %-20s | %s", pod.metadata.name, container.name, container.image),
			})
		end
	end

	pickers
		.new({}, {
			prompt_title = "Kubernetes Pods (Images)",
			finder = finders.new_table({
				results = pods,
				entry_maker = function(entry)
					return {
						value = entry,
						display = entry.display,
						ordinal = entry.container_name,
					}
				end,
			}),
			sorter = sorter({}),
			attach_mappings = function(_, map)
				-- <CR>: Show logs in tmux split
				map("i", "<CR>", function(prompt_bufnr)
					local selection = action_state.get_selected_entry().value
					actions.close(prompt_bufnr)
					local cmd =
						string.format("tmux split-window -h 'kubectl logs -f --tail 100 %s; read'", selection.pod_name)
					vim.fn.system(cmd)
				end)
				-- <C-r>: restart pod
				map("i", "<C-r>", function()
					local selection = action_state.get_selected_entry().value
					M.restart_pod(selection.container_name)
				end)
				-- <C-i>: Change image version
				map("i", "<C-i>", function(prompt_bufnr)
					local selection = action_state.get_selected_entry().value
					actions.close(prompt_bufnr)
					update_image(selection.pod_name, selection.container_name, selection.image)
				end)
				return true
			end,
		})
		:find()
end

return M
