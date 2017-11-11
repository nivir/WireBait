
--[[
    WireBait for Wireshark is a lua package to help write Wireshark 
    Dissectors in lua
    Copyright (C) 2015-2017 Markus Leballeux

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program; if not, write to the Free Software Foundation, Inc.,
    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
]]


local function verifyArgsType(...)  --TODO: ability to check optional args
    level = 2;
    i = 1;
    while true do
        expected_type = select(i, ...);
        if not expected_type then break end;
        var_name, var_val =  debug.getlocal(level,i);
        assert(type(var_val) == expected_type, "\nFunction " .. debug.getinfo(2).name .."() expected arg #".. i .." to be of type '" .. tostring(expected_type) .. "' but got '" .. type(var_val) .. "'!")
        i = i + 1;
    end
end

-- # wirebait dissector
local function createWirebaitDissector()
    local wirebait_dissector = {

    }

    local public_wb_dissector = {
        __is_wirebait_struct = true, --all wirebait data should have this flag so as to know their type
        __wirebait_type_name = "WirebaitDissector",

    }

    return public_wb_dissector;
end

-- # Wirebait Field
local function newWirebaitField(filter, name, size, ws_type_key, --[[optional]]display_val_map)
    verifyArgsType('string', 'string', 'number', 'string')
    local wb_field = { --private data
        m_filter = filter,
        m_name = name,
        m_size = size,
        m_type = ws_type_key,
        m_wireshark_field = Protofield[ws_type_key](filter, name, size, base, display_val_map);
    }

    local getFilter = function()
        return wb_field.m_filter;
    end

    local getName = function()
        return wb_field.m_name;
    end

    local getSize = function()
        return wb_field.m_size
    end

    local getWiresharkProtofield = function()
        return wb_field.m_wireshark_field;
    end
    
    local getType = function()
        return wb_field.m_type;
    end

    local pulic_wirebait_field_interface = {
        filter = getFilter,
        name = getName,
        size = getSize,
        wsProtofield = getWiresharkProtofield,
        type = getType,
    };

    return pulic_wirebait_field_interface;
end



-- # Wirebait Tree
local function newWirebaitTree(wb_fields_map, ws_tree, buffer, position, size, parent_wb_tree)
    local wb_tree = { --private data
        m_wb_fields_map = wb_fields_map; --reference to wirebait.created_protofields shared by all trees to keep track of new fields and register them
        m_ws_tree = ws_tree;
        m_buffer = buffer;
        m_start_position = position or 0;
        m_position = (position or 0), --+ (size or 0);
        m_end_position = (position or 0) + (size or buffer:len());
        m_parent = parent_wb_tree;
        m_is_root = not parent_wb_tree;
    }
    if size then assert(buffer:len() >= size, "Buffer is smaller than specified size!") end
    

    local getParent = function()
        return wb_tree.m_parent;
    end

    local getWiresharkTree = function ()
        return wb_tree.m_ws_tree;
    end

    local getBuffer = function()
        return wb_tree.m_buffer;
    end

    local getPosition = function()
        return wb_tree.m_position;
    end

    local skip = function(self, byte_count) --skip only affects the current tree and cannot go beyon the end_position
        --if not wb_tree.m_is_root then
        --   self:parent():skip(byte_count);
        --end
        assert(wb_tree.m_position + byte_count <= wb_tree.m_end_position , "Trying to skip more bytes than available in buffer managed by wirebait tree!")
        wb_tree.m_position = wb_tree.m_position + byte_count;
    end

    local fitHighlight = function(self, is_recursive, position) --makes highlighting fit the data from m_start_position to position or m_position
        position =  position or self:position();
        assert(position >= wb_tree.m_start_position, "Current position is before start position!");
        length = position - wb_tree.m_start_position
        wb_tree.m_ws_tree:set_len(length);
        if is_recursive and not wb_tree.m_is_root then
            self:parent():fitHighlight(is_recursive, position);
        end
    end

    local findOrAddProto = function(field_key, filter, name, type_key, size, base, display_val_map);
        if not wb_tree.m_wb_fields_map[field_key] then --adding new wb protofield if it doesn't exist
            wb_tree.m_wb_fields_map[field_key] = wirebait.field.new(filter, name, size, type_key, display_val_map);
        end
        return wb_tree.m_wb_fields_map[field_key];
    end

    local addTree = function (self, filter, name, type_key, size, b, display_map)
        base = base or base.DEC;
        field_key = "f_"..name:gsub('%W','') --Removes all non alpha-num chars from name and prepend 'f_'. For instance "2 Packets" becomes "f_2Packets"

        wb_proto_field = findOrAddProto(field_key, filter, name, type_key, size, base, display_val_map);

        --creating a new wireshart tree item and using it to create a new wb tree
        new_ws_tree = wb_tree.m_ws_tree:add(wb_proto_field.wsProtofield(), wb_tree.m_buffer(wb_tree.m_position, wb_proto_field.size()));
        new_wb_tree = newWirebaitTree(wb_tree.m_wb_fields_map, new_ws_tree, wb_tree.m_buffer, wb_tree.m_position, size, self)
        wb_tree.m_position = wb_tree.m_position + size;
        return new_wb_tree;
    end

    local addUint8 = function (self, filter, name, base, display_val_map) --display_val_map translated raw value on the wire into display value
        size = 1;
        value = wb_tree.m_buffer(wb_tree.m_position, size):le_uint();
        return addTree(self, filter, name, "uint8", size, base, display_val_map), value;
    end

    local addUint16 = function (self, filter, name, base, display_val_map) --display_val_map translated raw value on the wire into display value
        size = 2;
        value = wb_tree.m_buffer(wb_tree.m_position, size):le_uint();
        return addTree(self, filter, name, "uint16", size, base, display_val_map), value;
    end

    local addUint32 = function (self, filter, name, base, display_val_map) --display_val_map translated raw value on the wire into display value
        size = 4;
        value = wb_tree.m_buffer(wb_tree.m_position, size):le_uint();
        return addTree(self, filter, name, "uint32", size, base, display_val_map), value;
    end

    local addUint64 = function (self, filter, name, base, display_val_map) --display_val_map translated raw value on the wire into display value
        size = 8;
        value = wb_tree.m_buffer(wb_tree.m_position, size):le_uint64();
        return addTree(self, filter, name, "uint64", size, base, display_val_map), value;
    end

    local addString = function (self, filter, name, size, base, display_val_map) --display_val_map translated raw value on the wire into display value
        size = size or 1; -- using 1 if size of string is not provided
        value = wb_tree.m_buffer(wb_tree.m_position, size):string();
        return addTree(self, filter, name, "string", size, base, display_val_map), value;
    end
    
    local addStringz = function (self, filter, name, size, base, display_val_map) --display_val_map translated raw value on the wire into display value
        size = size or 1; -- using 1 if size of string is not provided
        value = wb_tree.m_buffer(wb_tree.m_position, size):stringz();
        return addTree(self, filter, name, "string", size, base, display_val_map), value;
    end

    local public_wirebait_tree_interface = {
        __is_wirebait_struct = true, --all wirebait data should have this flag so as to know their type
        __wirebait_type_name = "WirebaitTree",
        __buffer = getBuffer,
        parent = getParent,
        wiresharkTree = getWiresharkTree,
        position = getPosition,
        skip = skip,
        fitHighlight = fitHighlight,
        addUint8 = addUint8,
        addUint16 = addUint16,
        addUint32 = addUint32,
        addUint64 = addUint64,
        addString = addString,
        addStringz = addStringz
    }

    return public_wirebait_tree_interface;
end


--[[ Using a function to create the wirebait module so that it can have 
private state data ( 1 dissector per wirebait, and wirebait keeps track of protofields
so as to register them automatically)
]]--
local function publicWirebaitInterface() 
    local wirebait = { --wirebait state data which needs to be private
        m_created_proto_fields = {};
        m_size = 0,
        m_dissector = nil
    }

    function wirebait.createProtofield(filter, name, size, ws_protofield)
        new_pf = newWirebaitField(filter, name, size, ws_protofield)
        wirebait.m_created_proto_fields[wirebait.m_size] = new_pf
        wirebait.m_size = wirebait.m_size + 1;
        return new_pf
    end

    function wirebait.createTreeitem(arg1, arg2, ...)
        return newWirebaitTree(wirebait.m_created_proto_fields, arg1, arg2, unpack({...}));
    end

    function wirebait.createDissectorSingleton(name, abbrev_name)
        --checks('string', 'string');
        if not wirebait.m_dissector then
            wirebait.m_dissector = Proto(abbrev_name, name);
        else
            return wirebait.m_dissector;
        end
    end

    function getCreatedProtofieldCount()
        return wirebait.m_size;
    end

    return { --All functions available in wirebait package are named here
        field = { new = wirebait.createProtofield, count = getCreatedProtofieldCount },
        tree = { new = wirebait.createTreeitem },
        dissector = { newSingleton = wirebait.createDissectorSingleton }
    }
end

wirebait = publicWirebaitInterface() 
return wirebait

