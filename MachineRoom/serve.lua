local function setled(i)
    local f = assert(io.open("/sys/class/leds/tp-link\:blue\:system/brightness", "w"))
    f:write(i)
    f:close()
end

local function lock() setled(0) end
local function unlock() setled(255) end
    
lock()

-- Capture the output of system command
-- Shamelessly copied form http://stackoverflow.com/questions/132397/get-back-the-output-of-os-execute-in-lua
local function os.capture(cmd, raw)
  local f = assert(io.popen(cmd, 'r'))
  local s = assert(f:read('*a'))
  f:close()
  if raw then return s end
    s = string.gsub(s, '^%s+', '')
    s = string.gsub(s, '%s+$', '')
    s = string.gsub(s, '[\n\r]+', ' ')
  return s
end

-- Use the system command md5sum to findout the md5 checksum of certain string
local function md5sum(str)
  raw = os.capture('echo "' .. str .. '" | md5sum')
  md5 = string.sub(raw, 0, 32)
  return md5
end

-- Extract the 'pin' parameter from a HTTP request
local function getPin(firstLine)
  i, j = string.find(firstLine, '?pin=')
  pin = string.sub(firstLine, j + 1)
  i, j = string.find(pin, ' ')
  return string.sub(pin, 0, i - 1)
end

-- load namespace
local socket = require("socket")
-- create a TCP socket and bind it to the local host, at any port
local server = assert(socket.bind("*", 8080))
-- find out which port the OS chose for us
local ip, port = server:getsockname()
-- print a message informing what's up
print("Webserver running on port " .. port)
-- http header
local header = "HTTP/1.0 200 OK\r\nConnection: close\r\nContent-Type: text/html\r\n\r\n" ..
  "<html><head><title>XCJ Machine Room</title><meta name='viewport' content='width=120'></head><body onload='document.getElementById(\"pin\").focus()'>"
local footer = "</body></html>"

-- Salt added to the password before md5 hash
local password_salt = 'xinchejian'

-- Hardcoded password
local password_hash = '78b3087ef1365a27ac821832b0823473'

local function main ()
  -- wait for a connection from any client
  server:settimeout(30)
  local client, err = server:accept()
  if err then
    -- accept timed out - close the door
    lock()
  else
    -- make sure we don't block waiting for this client's line
    client:settimeout(1)
    -- receive the lines
    local firstLine = Nil
    while 1 do
      local line, err = client:receive()
      if not firstLine then firstLine = line end
      if line == "" then break end
      if err then break end
    end
    -- if there was no error, send it back to the client
    if md5sum(password_salt .. getPin(firstLine)) == password_hash then
      -- open the door
      unlock()
      client:send(header .. "Opened" .. footer)
    else
      client:send(header ..
        "<form method='GET' action='lock'>PIN <input id='pin' name='pin' type='password' maxlength='4' size='4'/> <input type='submit' value='Unlock'/></form>"..footer)
    end
    -- done with client, close the object
    client:close()
  end
end

-- loop forever waiting for clients
while 1 do
  pcall(main)
end
