local utils = require("cmp_tidal.utils")
local cmp = require("cmp")
local scan = require("plenary.scandir")

local source = {}

local default_option = {
    dirt_samples = utils.get_dirt_samples_path(),
    custom_samples = {},
}

source.is_available = function()
	return vim.bo.filetype == "tidal"
end

source.new = function()
	return setmetatable({}, { __index = source })
end

source._validate_options = function(_, params)
    local opts = vim.tbl_deep_extend("keep", params.option, default_option)

    -- Ensure dirt_samples is an array or convert it to an array
    if type(opts.dirt_samples) == "string" then
        opts.dirt_samples = { opts.dirt_samples }
    else
        print("Warning: Unexpected value for opts.dirt_samples. Using default value.")
        opts.dirt_samples = { utils.get_dirt_samples_path() }
    end

    -- Ensure custom_samples is an array or convert it to an array
    if type(opts.custom_samples) == "string" then
        opts.custom_samples = { opts.custom_samples }
    elseif type(opts.custom_samples) ~= "table" then
        opts.custom_samples = {}
    end

    -- Validate each path in the arrays
    for _, path in ipairs(vim.list_extend(opts.dirt_samples, opts.custom_samples)) do
        vim.validate({ samples = { path, "string" } })
    end

    return opts
end

source.complete = function(self, params, callback)
    local opts = self:_validate_options(params)
    local dirt_samples = opts.dirt_samples
    local custom_samples = opts.custom_samples

    local folder_table = {}

    local added_folders = {}  -- Table to keep track of added folders

    local function completePath(index, paths, source_type)
        if index <= #paths then
            local current_path = paths[index]
            if not added_folders[current_path] then
                added_folders[current_path] = true
                scan.scan_dir_async(current_path, {
                    depth = 1,
                    only_dirs = true,
                    on_exit = function(folders)
                        for _, folder in ipairs(folders) do
                            local folder_name = folder:match("^.+/(.+)$")
                            local folder_item = {
                                label = folder_name,
                                kind = cmp.lsp.CompletionItemKind.Folder,
                                path = folder,
                                source_type = source_type,  -- Set the source type flag
                            }
                            table.insert(folder_table, folder_item)
                        end

                        completePath(index + 1, paths, source_type)
                    end,
                })
            else
                completePath(index + 1, paths, source_type)
            end
        else
            callback({ items = folder_table, isIncomplete = true })  -- Send the results if folder_table is not empty
        end
    end

    completePath(1, custom_samples, "Custom Samples")  -- Set source type for custom samples
    completePath(1, dirt_samples, "Dirt Samples")      -- Set source type for dirt samples
end

source.resolve = function(_, completion_item, callback)
    local path = completion_item.path
    local source_type = completion_item.source_type
    
    scan.scan_dir_async(path, {
        depth = 1,
        search_pattern = { "%.wav$", "%.WAV$", "%.flac$", "%.FLAC$", "%.aiff$", "%.AIFF$" },
        on_exit = function(files)
            local files_table = {}
            for index, file in ipairs(files) do
                local file_name = file:match("^.+/(.+)$")
                table.insert(files_table, string.format("**:%s ::** %s", index, file_name))
            end

            -- Add documentation
            local file_count = #files_table
            local documentation_string = table.concat(files_table, "\n")
            local source_label = source_type or "Samples"
            completion_item.documentation = {
                kind = "markdown",
                value = string.format("**%s**: %s\n\n%s", source_label, file_count, documentation_string),
            }
            
            callback(completion_item)
        end,
    })
end

return source
