local LISTENPORT = 8080
-- Time-out between unlock() and lock()
local TIMEOUT = 20
-- Salt added to the password before md5 hash
local PASSWORD_SALT= 'xinchejian'
-- Hardcoded password
local PASSWORD_HASH = '78b3087ef1365a27ac821832b0823473'

local TESTING = true

-- Read all the contents of the specified file
local function readAll(fn)
  if not fn then return nil, "need filename" end
  local f, e = io.open(fn, 'r')
  local s = nil
  if f then
    s, e = f:read('*a')
    f:close()
  end
  return s, e
end

-- Write the contents to the specified file
local function writeAll(fn, contents)
  local f = assert(io.open(fn, 'w'))
  f:write(contents)
  f:close();
end


local function setled(i)
  if TESTING then return end
  writeAll("/sys/class/leds/tp-link\:blue\:system/brightness", i)
end

local function lock() setled(0) end
local function unlock() setled(255) end

-- Lock the door on program start
lock()

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
  local raw = os.capture('echo "' .. str .. '" | md5sum')
  return string.sub(raw, 0, 32)
end

-- Extract the 'pin' parameter from a HTTP request
local function getPin(query)
  return string.match(query, "pin=(%d+)")
end

-- Extract the 'message' parameter from a HTTP request
local function getMessage(query)
  return string.match(query, "message=([^&]+)")
end

-- Get the MAC address for the specified client IP
local function getMac(ip)
  local macs = os.capture("arp -a | grep " .. ip);
  return string.match(macs, "(%x%x[-:]%x%x[-:]%x%x[-:]%x%x[-:]%x%x[-:]%x%x)");
end

-- Parse the HTTP header into a triple: verb, resource, version
local function parseHttp(firstLine)
  if not firstLine then return nil end
  return string.match(firstLine, "(%u+) (.+) (.+)")
end

-- load namespace
local socket = require("socket")
local http = require("socket.http")
local url = require("socket.url")


print("Version 2")
-- create a TCP socket and bind it to the local host, at any port
local server = assert(socket.bind("*", LISTENPORT))
-- find out which port the OS chose for us
local ip, port = server:getsockname()
-- print a message informing what's up
print("Webserver running on port " .. port)
-- http header
local header = "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Type: text/html\r\nAccept: application/x-www-form-urlencoded\r\n\r\n" ..
  "<!DOCTYPE html><html><head><title>XCJ Machine Room</title><meta name='viewport' content='width=120'></head><body onload='document.getElementById(\"pin\").focus()'>"
local footer = "</body></html>"

-- This function makes the rabbit talk
local function rabbit(message)
  if not TOKEN then TOKEN = readAll("tts-token") end
  if not message then message = "hello" end
  http.request("http://api.wizz.cc/?sn=001D92164E18&token=" .. TOKEN .. "&server=violet&tts=" .. url.escape(message:lower()) .. ".&voice=en")
end

-- Returns an HTML safe version of the specified string
local function xmlEncode(str)
  str = str:gsub('&', "&amp;")--this one first
  str = str:gsub('\'', "&#39;")
  str = str:gsub('\"', "&quot;")
  str = str:gsub('<', "&lt;")
  return str:gsub('>', "&gt;")
end


local function main ()
  -- wait for a connection from any client
  server:settimeout(TIMEOUT)
  local client, err = server:accept()
  if err then
    -- accept() timed out - close the door
    lock()
  else
    -- make sure we don't block waiting for this client's line
    client:settimeout(1)

    -- receive the first line
    local firstLine, err = client:receive()

    -- ignore all the headers
    while true do
      local line, err = client:receive()
      if err then break end
      if line == "" then break end        -- headers are done
    end

    -- who is this?
    local ip = client:getpeername()
    local mac = getMac(ip)
    if TESTING and not mac then mac="11-22-33-44-55-66" end

    local verb, resource = parseHttp(firstLine)
    if verb == "GET" and resource == "/" then

      -- Index page; check whether the client has a known MAC address
      local message = readAll(mac)
      if message then
        -- Registered MAC address: open the door and play a message
        unlock()
        client:send(header .. "<h1>Welcome back</h1><h3>Edit your personalized message</h3>")
        client:send("<form method='POST' action='/'>PIN <input id='pin' name='pin' type='number' maxlength='4' size='4'/> <input type='text' name='message' value='"..xmlEncode(message).."'/> <input type='submit' value='Modify'/></form>" .. footer);
        --rabbit(message)
      else
        -- Default response: the PIN page
        client:send(header .. "<form method='POST' action='/'>PIN <input id='pin' name='pin' type='number' maxlength='4' size='4'/> <input type='submit' value='Unlock'/></form>" .. footer);
      end

    elseif verb == "POST" and resource == "/" then

      -- Receive all the POST data
      local content, err, pr = client:receive('*a')
      local pin = getPin(pr)
      -- if there was no error, send response back to the client
      if pin and md5sum(PASSWORD_SALT.. pin) == PASSWORD_HASH then

        local message = getMessage(pr)
        if message then
		  -- URL-decode the message (LUA doesn't handle the +)
		  message = url.unescape(message:gsub('+',' '))
          -- Register this MAC address
          writeAll(mac, message)
          -- Test the registration by redirecting to the index page
          client:send("HTTP/1.1 302 Found\r\nLocation: /\r\n\r\n")
        else
          -- open the door
          unlock()
          --socket.sleep(2)
          --lock()
          -- This user is not yet registered (wouldn't get here otherwise)
          if ip == "10.0.10.2" then
            -- No registration page for WAN clients
            client:send(header .. "<h1>Opened</h1>" .. footer)
          else
            client:send(header .. "<h1>Opened</h1><h3>Register your personalized message</h3>")
            client:send("<form method='POST' action='/'>PIN <input id='pin' name='pin' type='number' maxlength='4' size='4'/> <input name='message' type='text'/><input type='submit' value='Register'/></form>" .. footer);
          end
          message = readAll("default-message")
          rabbit(message)
          -- remove any message for this MAC
          os.remove(mac)
        end

      else
        -- MD5 mismatch
        client:send(header .. "<h1>Wrong PIN</h1>" .. footer)
        -- hack protection
        socket.sleep(4)
      end

    else

      -- 404
      client:send("HTTP/1.1 404 Not Found\r\n\r\n")

    end
    -- done with client, close the object
    client:close()
  end
end

-- loop forever waiting for clients
while 1 do
  local status, err = pcall(main)
  if not status then print(err) end
end
