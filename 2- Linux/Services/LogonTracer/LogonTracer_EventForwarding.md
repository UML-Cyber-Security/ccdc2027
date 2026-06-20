# Event log forwarding for logonTracer
Author: Ofir and Irakli\
Event log forwarding for logonTracer

> [!IMPORTANT]
> First you need at least 2 joined windows machines, an event forwarder and a collector


### On the event forwarder machines:
1. Check winRM is enabled by running the following in powershell:
    ```powershell
    winrm quickconfig
    ```
    If its not running type Y and hit enter
2. Open **Computer Managment** -> **Local Users and Groups** -> **Groups** -> double click **Event Log Readers** -> **add** -> **Object Types** -> enable **Computers** -> **ok** -> type the name of your collector -> **Check Names** -> **ok** -> **ok**
### On the event collector machine:
1. Open **Event Viewer** -> right click **Subscriptions** -> **Create Subscription**
2. Name the Subscription
3. Destination logs: Forwarded Events
4. Subscription type: for small scale, press **Collector Initiated**
5. Press **Select Computers** -> **Add domain computers** -> type the name of your computers -> press **check names** -> **ok** -> **Test** -> **ok** -> **ok**
6. Select events: 
    - Press: **Critical**, **Warning**, **Error**, **Information**.
    - **event logs** -> **Windows logs** -> enable **Secuirty**. 
    - Event Ids: 4624,4625,4672,4768,4769,4776
7. Advance: press **Minimal Latency** for 30s log retrival. press **ok**
8. Press **ok**

### On the event forwarder machines:
run these following commands in powershell in enable secuirty log forwarding
```powershell
wevtutil sl Security /ca:"O:BAG:SYD:(A;;0x1;;;NS)"
net stop wecsvc
net start wecsvc
```