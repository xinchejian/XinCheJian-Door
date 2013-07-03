local socket = require("socket")

-- Write the contents to the specified file
local function writeAll(fn, contents)
  local f = assert(io.open(fn, 'w'))
  f:write(contents)
  f:close();
end

local function writeio(i, val)
  if TESTING then return end
  writeAll("/sys/class/gpio/gpio"..i.."/value", val)
end

local function lock()
  writeio('0', '1')
  socket.sleep(1)
  writeio('0', '0')
end

local function unlock()
  writeio('29', '1')
  socket.sleep(1)
  writeio('29', '0')
end

--lock()

-- Capture the output of system command
-- Shamelessly copied form http://stackoverflow.com/questions/132397/get-back-the-output-of-os-execute-in-lua
function os.capture(cmd, raw)
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
  --string.match("asdf?pin=2343", ".*[&?]pin=(%d%d%d%d)")
  i, j = string.find(firstLine, '?pin=')
  if(i == nil) then return '' end
  pin = string.sub(firstLine, j + 1)
  i, j = string.find(pin, ' ')
  if(i == nil) then return pin end
  return string.sub(pin, 0, i - 1)
end

-- load namespace
local http = require("socket.http")
-- create a TCP socket and bind it to the local host, at any port
local server = assert(socket.bind("*", 80))
-- find out which port the OS chose for us
local ip, port = server:getsockname()
-- print a message informing what's up
print("Webserver running on port " .. port)
-- http header
local header = "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Type: text/html\r\n\r\n" ..
  "<html><head><title>XCJ Machine Room</title><meta name='viewport' content='width=120'></head><body onload='document.getElementById(\"pin\").focus()'>"
local footer = "</body></html>"

-- Salt added to the password before md5 hash
local password_salt = 'xinchejian'

-- Hardcoded password
local password_hash = 'a2b99d32956e56fa9bbddca655a489b2'

local function main ()
	-- make sure we don't block waiting for this client's line
	client:settimeout(1)
	-- receive the lines
	local firstLine = nil
	while 1 do
	  local line, err = client:receive()
	  if not firstLine then firstLine = line end
	  if line == "" then break end
	  if err then break end
	end
	-- if there was no error, send response back to the client
	if md5sum(password_salt .. getPin(firstLine)) == password_hash then
	  -- open the door
	  unlock()
	  --socket.sleep(2)
	  --lock()
	  client:send(header .. "Opened" .. footer)
	  http.request("http://api.wizz.cc/?sn=001D92164E18&token=89442562-4e58-439f-8460-a4fde1e6da47&server=violet&tts=hello.&voice=en")

	else
	  -- wrong code (or first time)
	  client:send(header ..
		"<form method='GET' action='lock'>PIN <input id='pin' name='pin' type='password' maxlength='4' size='4'/> <input type='submit' value='Unlock'/></form>"..footer)
	  -- hack protection
	  socket.sleep(4)
	end
end

server:settimeout(20)
-- loop forever waiting for clients
while 1 do
  -- wait for a connection from any client, or timeout at 20sec.
  client, err = server:accept()
  if err then
    -- accept timed out - close the door
    lock()
  else
    pcall(main)
	-- done with client, close the object
	client:close()
  end
end
