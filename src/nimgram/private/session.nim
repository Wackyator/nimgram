import network/transports
import random/urandom
import rpc/raw
import rpc/decoding
import rpc/encoding
import asyncdispatch
import crypto/aes
import stew/endians2
import nimcrypto
import math
import updates
import storage
import times
import tables
type Response = ref object
    event: AsyncEvent
    body: TL

type Session* = ref object 
    authKey: seq[uint8]
    authKeyID: seq[uint8]
    storageManager: NimgramStorage
    serverSalt: seq[uint8]
    dcID: int
    activeReceiver: bool
    sessionID: seq[uint8] 
    seqNo: int 
    callbackUpdates: UpdatesCallback
    acks: seq[int64]
    responses: Table[int64, Response]
    maxMessageID: uint64
    connection: MTProtoNetwork

proc messageID(self: Session): uint64 =
    result = uint64(now().toTime().toUnix()*2 ^ 32)
    doAssert result mod 4 == 0, "message id is not divisible by 4, consider syncing your time."

    if result <= self.maxMessageID:
        result = self.maxMessageID + 4
    self.maxMessageID = result

proc setCallback*(self: Session, callback: proc(updates: UpdatesI): Future[void] {.async.}) =
    self.callbackUpdates.setCallback(callback)

proc initSession*(connection: MTProtoNetwork, dcID: int, authKey: seq[uint8], serverSalt: seq[uint8], storageManager: NimgramStorage): Session =
    result = new Session
    result.acks = newSeq[int64](0)
    result.connection = connection
    result.dcID = dcID
    result.authKey = authKey
    result.authKeyID = sha1.digest(authKey).data[12..19]
    result.storageManager = storageManager
    result.serverSalt = serverSalt
    result.callbackUpdates = UpdatesCallback()
    result.seqNo = 5
    result.sessionID = urandom(4) & uint32(now().toTime().toUnix()).TLEncode()

type EncryptedResult = object
    encryptedData: seq[uint8]
    messageID: uint64

proc encrypt*(self: Session, obj: seq[uint8], typeof: TL): EncryptedResult =

    var data = obj
    var seqNumber = seqNo(typeof, self.seqNo)
    self.seqNo = seqNumber
    var mesageeID = self.messageID()
    result.messageID = mesageeID
    var payload = self.serverSalt &  self.sessionID &  mesageeID.TLEncode() & uint32(seqNumber).TLEncode() & uint32(len(data)).TLEncode() & data
    payload.add(urandom((len(payload) + 12) mod 16 + 12) )
    while true:
        if len(payload) mod 16 ==  0 and len(payload) mod 4 == 0:
            break
        payload.add(1)
    var messageKey = sha256.digest(self.authKey[88..119] & payload).data[8..23]
    var a = sha256.digest(messageKey & self.authKey[0..35]).data
    var b = sha256.digest(self.authKey[40..75] & messageKey).data

    var aesKey = a[0..7] & b[8..23] & a[24..31]
    var aesIV = b[0..7] & a[8..23] & b[24..31]
    result.encryptedData = self.authKeyID & messageKey & aesIGE(aesKey, aesIV, payload, true)


proc decrypt(self: Session, data: seq[uint8]): CoreMessage =
    var sdata = newScalingSeq(data)
    var authKeyId = sdata.readN(8)
    doAssert authKeyId == self.authKeyID, "Response Auth Key Id is different from saved one"
    var responseMsgKey = sdata.readN(16)
    var a = sha256.digest(responseMsgKey & self.authKey[8..43]).data
    var b = sha256.digest(self.authKey[48..83] & responseMsgKey).data
    var aesKey = a[0..7] & b[8..23] & a[24..31]
    var aesIv = b[0..7] & a[8..23] & b[24..31]
    var encryptredata = sdata.readAll()
    var plaintext = aesIGE(aesKey, aesIv, encryptredata, false)
    var msgKey = sha256.digest(self.authKey[96..(96+31)] & plaintext).data[8..23]
    doAssert msgKey == responseMsgKey, "Computed Msg Key is different from response"
    var splaintext = newScalingSeq(plaintext)
    discard splaintext.readN(8)
    var responseSessionID = splaintext.readN(8)
    result = new CoreMessage
    result.TLDecode(splaintext)

proc send*(self: Session, tl: TL, waitResponse: bool = true): Future[TL] {.async.} 

proc startHandler*(self: Session) {.async.} = 
    while not self.connection.isClosed():
        var mdata = await self.connection.receive()
        if len(mdata) == 4:
            raise newException(Exception, "invalid response: " & $(cast[int32](fromBytes(uint32, mdata))))
        var coreMessageDecrypted = self.decrypt(mdata)

        var messages: seq[CoreMessage]

        if coreMessageDecrypted.body of MessageContainer:
            messages = coreMessageDecrypted.body.MessageContainer.messages
        else:
            messages = @[coreMessageDecrypted]
        for message in messages:
            var body = message.body
            if not message.seqNo mod 2 == 0:
                if self.acks.contains(message.msgID.int64):
                    continue
                else:
                    self.acks.add(message.msgID.int64)
            
            var msgID = int64(0)
            self.seqNo = seqNo(body, self.seqNo)
            if message.body of Msg_detailed_info:
                self.acks.add(body.Msg_detailed_info.answer_msg_id)
                continue
            if message.body of Msg_new_detailed_info:
                self.acks.add(body.Msg_new_detailed_info.answer_msg_id)
                continue

            if message.body of New_session_created:
                continue

            if message.body of Bad_msg_notification:
                msgID = body.Bad_msg_notification.bad_msg_id

            if message.body of Bad_server_salt:
                msgID = body.Bad_server_salt.bad_msg_id

            if message.body of FutureSalts:
                msgID = body.FutureSalts.reqMsgID.int64
            
            if message.body of Rpc_result:
                msgID = body.Rpc_result.req_msg_id
                body = body.Rpc_result.result
            
            if body of GZipPacked:
                body = body.GZipPacked.body

            if message.body of Pong:
                msgID = body.Pong.msgID
            
            if self.responses.contains(msgID):
                self.responses[msgID].body = body
                self.responses[msgID].event.trigger()
            
            if body of UpdatesTooLong or body of UpdateShortMessage or body of UpdateShortChatMessage or body of UpdateShort or body of UpdatesCombined or body of raw.Updates:
                asyncCheck self.callbackUpdates.processUpdates(body.UpdatesI)
                

            if len(self.acks) >= 8:
                discard await self.send(Msgs_ack(msg_ids: self.acks), false)
                self.acks.setLen(0)

            
            

proc waitEvent(ev: AsyncEvent): Future[void] =
   var fut = newFuture[void]("waitEvent")
   proc cb(fd: AsyncFD): bool = fut.complete(); return true
   addEvent(ev, cb)
   return fut



proc send*(self: Session, tl: TL, waitResponse: bool = true): Future[TL] {.async.} =
    var data = self.encrypt(tl.TLEncode(), tl)
    await self.connection.write(data.encryptedData)
    if waitResponse:
        self.responses[data.messageID.int64] = Response(event: newAsyncEvent())

        await waitEvent(self.responses[data.messageID.int64].event)
        var response = self.responses[data.messageID.int64].body
        if response of Bad_server_salt:
            var badServerSalt = response.Bad_server_salt
            self.serverSalt = badServerSalt.new_server_salt.TLEncode()
            var info = await self.storageManager.GetSessionsInfo()
            info[self.dcID].salt = self.serverSalt
            await self.storageManager.WriteSessionsInfo(info)
            return await self.send(tl)
        if response of Rpc_error:
            var excp = RPCException(errorMessage: response.Rpc_error.error_message, errorCode: response.Rpc_error.error_code)
            excp.msg = response.Rpc_error.error_message
            raise excp
            #raise newException(CatchableError, response.Rpc_error.error_message, RPCException(errorCode: response.Rpc_error.error_code, errorMessage: response.Rpc_error.error_message))

        if response of InvokeWithoutUpdates:
            response = response.InvokeWithoutUpdates.query
        if response of InvokeWithTakeout:
            response = response.InvokeWithTakeout.query

        return response