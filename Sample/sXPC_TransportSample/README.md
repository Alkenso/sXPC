# XPCTransport sample

The intent of the sample is brief overview of `XPCTransport` layer and it benefits 

The sample shows two pretty common, close to real-world scenarios:
1. Receiving remote notifications
2. Sending analytic events

## Sample components
#### App
- has GUI
- produces analytic events on buttons click. Analytic events are sent over `XPCService`
- receives remove notificatons through `XPCService`. Notifications may or may not require the answer 

#### XPCService
- background XPC service process
- receives analytic events from the `App` (emulate their sending to the remote server)
- generate periodic notification events and post the to the `App` (emulate receiving remote notifications from the server)
