--[[
    lua code that mocks wireshark lua api to test wirebait
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

local wireshark_mock = { protofield = {}, treeitem = {}, buffer = {} };

function wireshark_mock.protofield.new(name, abbr, _type)
    assert(name and abbr and _type, "Protofiled argument should not be nil!")
    local protofield = {
            m_name = name;
            m_abbr = abbr;
            m_type = _type;
        }
        
    return protofield;
end

function wireshark_mock.treeitem.new() 
    local treeitem = {
        m_length = 0;
        m_subtrees = {};
        m_subtrees_count = 0;
    }

    function treeitem:set_len(L)
        self.m_length = L;
    end
    
    function treeitem:add(protofield)
        print("Added protofield " .. protofield.m_name .. ".");
        self.m_subtrees[self.m_subtrees_count] = { proto_field = protofield, treeitem = wireshark_mock.treeitem.new() };
        return self.m_subtrees[self.m_subtrees_count].treeitem;
    end

    return treeitem;
end

function wireshark_mock.buffer.new(size)
    return {
        m_length = size or 0,

        len = function()
            return m_length
        end
    }
end

return wireshark_mock;


