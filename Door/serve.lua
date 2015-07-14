-- load namespace
local socket = require("socket")
local http = require("socket.http")
local url = require("socket.url")
local ltn12 = require("ltn12")

local LISTENPORT = 80
-- Salt added to the password before md5 hash
local PASSWORD_SALT= 'xinchejian'
-- Hardcoded password
local PASSWORD_HASH = '78b3087ef1365a27ac821832b0823473'
-- local boolean flag to auto lock after a certain time
local UNLOCKED = 0

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

-- Extract the 'action' parameter from a HTTP request
local function getAction(query)
  return string.match(query, "action=(%w+)")
end

-- Get the MAC address for the specified client IP
local function getMac(ip)
  local macs = os.capture("cat /proc/net/arp | grep " .. ip);
  return string.match(macs, "(%x%x[-:]%x%x[-:]%x%x[-:]%x%x[-:]%x%x[-:]%x%x)");
end

-- Send lock command to arduino
local function lock()
  os.execute('echo c > /dev/ttyACM0')
  UNLOCKED = 0
end

-- Send lock command to arduino
local function unlock()
  os.execute('echo o > /dev/ttyACM0')
  UNLOCKED = 1
end

-- Parse the HTTP header into a triple: verb, resource, version
local function parseHttp(firstLine)
  if not firstLine then return nil end
  return string.match(firstLine, "(%u+) (.+) (.+)")
end

print("Version 2")
print("Setting up arduino")
os.execute('stty -F /dev/ttyACM0 cs8 115200 ignbrk -brkint -icrnl -imaxbel -opost -onlcr -isig -icanon -iexten -echo -echoe -echok -echoctl -echoke noflsh -ixon -crtscts')
-- create a TCP socket and bind it to the local host, at any port
local server = assert(socket.bind("*", LISTENPORT))
-- find out which port the OS chose for us
local ip, port = server:getsockname()
-- print a message informing what's up
print("Webserver running on port " .. port)
-- lock the door
os.execute('echo c > /dev/ttyACM0')
-- http header
local headers = "HTTP/1.1 100 continue\r\n\r\nHTTP/1.1 200 OK\r\nConnection: close\r\nContent-Type: text/html\r\nAccept: application/x-www-form-urlencoded\r\nversion: HTTP/1.1\r\n\r\n"
local template = "<!DOCTYPE html><html><head><title>XCJ Door</title><meta name='viewport' content='width=120'></head><body onload='document.getElementById(\"pin\").focus()'>${{content}}</body></html>\r\n\r\n"
local keypad = "<form method='POST' action='/'><input type='number' pattern='[0-9]*' name='pin' id='pin'/><br/><input type='submit' name='action' value='open'/><input type='submit' name='action' value='lock'/></form>"
local openning = "<h2>Gate opening</h2>"
local locking = "<h2>Gate locking</h2>"
local wrongPin = "<h2>Pin entered is not correct.</h2>" .. keypad;

-- Returns an HTML safe version of the specified string
local function xmlEncode(str)
  str = str:gsub('&', "&amp;")--this one first
  str = str:gsub('\'', "&#39;")
  str = str:gsub('\"', "&quot;")
  str = str:gsub('<', "&lt;")
  return str:gsub('>', "&gt;")
end

-- Renders html block into the page template
local function render(content)
  return template:gsub('\${{content}}', content)
end

-- Renders the keypad page
local function renderKeypad(client)
    client:send(render(keypad))
end

-- Check client post and opens the door
local function checkPin(pr)
  local pin = getPin(pr)
  -- if there was no error, send response back to the client
  if pin and md5sum(PASSWORD_SALT.. pin) == PASSWORD_HASH then
    return true;
  else
    return false;
  end
end

local function postOpenerMacAddr(mac, action)
  local googleFormUrl = 'https://docs.google.com/forms/d/1XyIrxZlNkdkYCzFxI0g_EaMK9ymZLrix87z7u7VqAwY/formResponse';
  mac = str:gsub(':', "%3A");
  local req_body = 'entry.360556683=' .. mac .. '&entry.555954297=' .. action;
  local headers = {
    ["Content-Type"] = "application/x-www-form-urlencoded";
    ["Content-Length"] = #req_body;
  }

  client, code, headers, status = http.request{
    url=googleFormUrl,
    sink=ltn12.sink.table(resp),
    method="POST",
    headers=headers,
    source=ltn12.source.string(req_body)
  }
  return resp;
end

local function main ()
  
  local dow = tonumber(os.date("%w"))                                      
  local hour = tonumber(os.date("%H"))                                      
  -- Auto-lock the door, except on Wednesday's betwen 7 and 9pm
  if ((hour <= 18 or hour >= 21 or dow ~= 3) and UNLOCKED == 1) then                                        
    print "Locking Door"
    os.execute('`sleep 5; echo c > /dev/ttyACM0` 2>&1 ')                    
  end
   
  local TIMEOUT = 15 * 60
  
  -- wait for a connection from any client
  server:settimeout(TIMEOUT)
  local client, err = server:accept()
  if err then
    -- Do nothing
  else
    -- make sure we don't block waiting for this client's line
    client:settimeout(0.1)

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

    local verb, resource = parseHttp(firstLine)
    if verb == "GET" and resource == "/" then
      renderKeypad(client)
    elseif verb == "POST" then
      -- Receive all the POST data
      local content, err, pr = client:receive('*a')
      if checkPin(pr) then
        local action = getAction(pr)
        if action == "open" then
          unlock();
          --postOpenerMacAddr(mac, 'open');
          client:send(render(openning))
        elseif action == "lock" then
          lock();
          --postOpenerMacAddr(mac, 'lock');
          client:send(render(locking))
        end
      else
        client:send(render(wrongPin))
        socket.sleep(4);
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
