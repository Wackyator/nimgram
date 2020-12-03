import bigints
import stint
import stint/intops
import strutils
import tables

#i hate openssl

type Key = object
    e: string
    n: string

const Keychain* = {847625836280919973'i64: Key(n: "22081946531037833540524260580660774032207476521197121128740358761486364763467087828766873972338019078976854986531076484772771735399701424566177039926855356719497736439289455286277202113900509554266057302466528985253648318314129246825219640197356165626774276930672688973278712614800066037531599375044750753580126415613086372604312320014358994394131667022861767539879232149461579922316489532682165746762569651763794500923643656753278887871955676253526661694459370047843286685859688756429293184148202379356802488805862746046071921830921840273062124571073336369210703400985851431491295910187179045081526826572515473914151", e:"65537"),
                1562291298945373506'i64: Key(n: "23978758553106631992002580305620005835060400692492410830911253690968985161770919571023213268734637655796435779238577529598157303153929847488434262037216243092374262144086701552588446162198373312512977891135864544907383666560742498178155572733831904785232310227644261688873841336264291123806158164086416723396618993440700301670694812377102225720438542027067699276781356881649272759102712053106917756470596037969358935162126553921536961079884698448464480018715128825516337818216719699963463996161433765618041475321701550049005950467552064133935768219696743607832667385715968297285043180567281391541729832333512747963903", e:"65537"),
                -5859577972006586033'i64: Key(n: "22718646979021445086805300267873836551952264292680929983215333222894263271262525404635917732844879510479026727119219632282263022986926715926905675829369119276087034208478103497496557160062032769614235480480336458978483235018994623019124956728706285653879392359295937777480998285327855536342942377483433941973435757959758939732133845114873967169906896837881767555178893700532356888631557478214225236142802178882405660867509208028117895779092487773043163348085906022471454630364430126878252139917614178636934412103623869072904053827933244809215364242885476208852061471203189128281292392955960922615335169478055469443233", e:"65537"),
                6491968696586960280'i64: Key(n:"24037766801008650742980770419085067708599000106468359115503808361335510549334399420739246345211161442047800836519033544747025851693968269285475039555231773313724462564908666239840898204833183290939296455776367417572678362602041185421910456164281750840651140599266716366431221860463163678044675384797103831824697137394559208723253047225996994374103488753637228569081911062604259973219466527532055001206549020539767836549715548081391829906556645384762696840019083743214331245456023666332360278739093925808884746079174665122518196162846505196334513910135812480878181576802670132412681595747104670774040613733524133809153", e:"65537"),
#old
                -4344800451088585951'i64: Key(n: "24403446649145068056824081744112065346446136066297307473868293895086332508101251964919587745984311372853053253457835208829824428441874946556659953519213382748319518214765985662663680818277989736779506318868003755216402538945900388706898101286548187286716959100102939636333452457308619454821845196109544157601096359148241435922125602449263164512290854366930013825808102403072317738266383237191313714482187326643144603633877219028262697593882410403273959074350849923041765639673335775605842311578109726403165298875058941765362622936097839775380070572921007586266115476975819175319995527916042178582540628652481530373407" ,e: "65537"),
                -7306692244673891685'i64: Key(n: "25081407810410225030931722734886059247598515157516470397242545867550116598436968553551465554653745201634977779380884774534457386795922003815072071558370597290368737862981871277312823942822144802509055492512145589734772907225259038113414940384446493111736999668652848440655603157665903721517224934142301456312994547591626081517162758808439979745328030376796953660042629868902013177751703385501412640560275067171555763725421377065095231095517201241069856888933358280729674273422117201596511978645878544308102076746465468955910659145532699238576978901011112475698963666091510778777356966351191806495199073754705289253783", e: "65537"),
                -5738946642031285640'i64: Key(n: "22347337644621997830323797217583448833849627595286505527328214795712874535417149457567295215523199212899872122674023936713124024124676488204889357563104452250187725437815819680799441376434162907889288526863223004380906766451781702435861040049293189979755757428366240570457372226323943522935844086838355728767565415115131238950994049041950699006558441163206523696546297006014416576123345545601004508537089192869558480948139679182328810531942418921113328804749485349441503927570568778905918696883174575510385552845625481490900659718413892216221539684717773483326240872061786759868040623935592404144262688161923519030977", e: "65537"),
                8205599988028290019'i64: Key(n: "24573455207957565047870011785254215390918912369814947541785386299516827003508659346069416840622922416779652050319196701077275060353178142796963682024347858398319926119639265555410256455471016400261630917813337515247954638555325280392998950756512879748873422896798579889820248358636937659872379948616822902110696986481638776226860777480684653756042166610633513404129518040549077551227082262066602286208338952016035637334787564972991208252928951876463555456715923743181359826124083963758009484867346318483872552977652588089928761806897223231500970500186019991032176060579816348322451864584743414550721639495547636008351", e: "65537")
}

type RSA* = object
    e: StUint[2048]
    n: StUint[2048]


proc norm(data: seq[uint32]): seq[uint32] = 
    var i = len(data)
    while i > 0 and data[i-1] == 0:
        dec(i)
    return data[0..(i-1)]

proc encodeToSeqUint(data:  seq[uint8]): seq[uint32] =
    if len(data) mod 4 != 0:
        raise newException(Exception, "needs to be divisible by 4")
    var realLen = len(data) div 4
    var i: int = int(0)
    var m = 0
    while i != realLen:
        var tempInt: uint32
        var toCopy = data[m..(m+3)]
        copyMem(addr tempInt, addr toCopy[0], 4)
        inc(i)
        m += 4
        result.add(tempInt)
    return norm(result)
        
proc encodeToBytes(data: seq[uint32]): seq[uint8] =
    for unit in data:
        var tempBytes = cast[array[0..3, uint8]](unit)
        result.add(tempBytes[0..3])

proc initRSA*(id: int64): RSA =
    var keychainTable = Keychain.toTable()
    if not keychainTable.contains(id):
        raise newException(Exception, "key not found")
    var nbytes = keychainTable[id].n.initBigInt().limbs.encodeToBytes()
    result.n = fromBytes(StUint[2048], nbytes, cpuEndian)

    #exponent should stay in int
    result.e = stuint(parseBiggestUInt(keychainTable[id].e), 2048)
 

proc encrypt*(self: RSA, data: seq[uint8]): seq[uint8] =
    var m = fromBytes(StUint[2048], data, bigEndian)
    #note: this procedure call seems broken on nimsuggest, but it's actually correct (compiles without any problem)
    var pmod = powmod(m, self.e, self.n)
    return toBytesBE(pmod)[0..255]
    