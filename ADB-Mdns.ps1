# Cliente mDNS minimo. Windows (red "Publica") suele bloquear lo que usa `adb mdns`,
# asi que se consulta directo: multicast por cada interfaz (con bit QU, para que el
# celular conteste por unicast) y, si se conoce, unicast directo a la IP del celular.

if (-not ("MdnsLite" -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;

public static class MdnsLite
{
    static byte[] Build(string name, int type, bool qu)
    {
        var ms = new MemoryStream();
        ms.Write(new byte[] { 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0 }, 0, 12);
        foreach (var label in name.Split('.'))
        {
            var b = Encoding.UTF8.GetBytes(label);
            ms.WriteByte((byte)b.Length);
            ms.Write(b, 0, b.Length);
        }
        ms.WriteByte(0);
        ms.WriteByte((byte)(type >> 8)); ms.WriteByte((byte)type);
        ms.WriteByte((byte)(qu ? 0x80 : 0x00)); ms.WriteByte(1);
        return ms.ToArray();
    }

    static string ReadName(byte[] b, ref int pos)
    {
        var sb = new StringBuilder();
        int p = pos; bool jumped = false; int guard = 0;
        while (p < b.Length && guard++ < 64)
        {
            int len = b[p];
            if (len == 0) { p++; break; }
            if ((len & 0xC0) == 0xC0)
            {
                int ptr = ((len & 0x3F) << 8) | b[p + 1];
                if (!jumped) pos = p + 2;
                jumped = true; p = ptr; continue;
            }
            sb.Append(Encoding.UTF8.GetString(b, p + 1, len)).Append('.');
            p += 1 + len;
        }
        if (!jumped) pos = p;
        return sb.ToString().TrimEnd('.');
    }

    // Devuelve filas { nombre, tipo (PTR|SRV|A), dato, ipRemitente }.
    // SRV: dato = "puerto;host".
    public static List<string[]> Query(string name, int type, string unicastIp, int timeoutMs)
    {
        var rows = new List<string[]>();
        var socks = new List<Socket>();
        var query = Build(name, type, true);
        var mcast = new IPEndPoint(IPAddress.Parse("224.0.0.251"), 5353);

        foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (ni.OperationalStatus != OperationalStatus.Up) continue;
            if (ni.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
            foreach (var ua in ni.GetIPProperties().UnicastAddresses)
            {
                if (ua.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                try
                {
                    var s = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
                    s.Bind(new IPEndPoint(ua.Address, 0));
                    s.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.MulticastInterface, ua.Address.GetAddressBytes());
                    s.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.MulticastTimeToLive, 255);
                    s.SendTo(query, mcast);
                    if (!string.IsNullOrEmpty(unicastIp))
                        s.SendTo(query, new IPEndPoint(IPAddress.Parse(unicastIp), 5353));
                    socks.Add(s);
                }
                catch { }
            }
        }

        var deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
        var buf = new byte[9000];
        while (DateTime.UtcNow < deadline && socks.Count > 0)
        {
            var ready = new List<Socket>(socks);
            Socket.Select(ready, null, null, 100000);
            foreach (var s in ready)
            {
                try
                {
                    EndPoint from = new IPEndPoint(IPAddress.Any, 0);
                    int n = s.ReceiveFrom(buf, ref from);
                    Parse(buf, n, ((IPEndPoint)from).Address.ToString(), rows);
                }
                catch { }
            }
        }
        foreach (var s in socks) { try { s.Close(); } catch { } }
        return rows;
    }

    static void Parse(byte[] b, int n, string sender, List<string[]> rows)
    {
        try
        {
            if (n < 12) return;
            int qd = (b[4] << 8) | b[5];
            int rr = ((b[6] << 8) | b[7]) + ((b[8] << 8) | b[9]) + ((b[10] << 8) | b[11]);
            int pos = 12;
            for (int i = 0; i < qd; i++) { ReadName(b, ref pos); pos += 4; }
            for (int i = 0; i < rr && pos < n; i++)
            {
                string name = ReadName(b, ref pos);
                int type = (b[pos] << 8) | b[pos + 1];
                int rdlen = (b[pos + 8] << 8) | b[pos + 9];
                int rd = pos + 10;
                pos = rd + rdlen;
                if (type == 12)
                {
                    int p = rd;
                    rows.Add(new[] { name, "PTR", ReadName(b, ref p), sender });
                }
                else if (type == 33)
                {
                    int port = (b[rd + 4] << 8) | b[rd + 5];
                    int p = rd + 6;
                    rows.Add(new[] { name, "SRV", port + ";" + ReadName(b, ref p), sender });
                }
                else if (type == 1 && rdlen == 4)
                {
                    rows.Add(new[] { name, "A", b[rd] + "." + b[rd + 1] + "." + b[rd + 2] + "." + b[rd + 3], sender });
                }
            }
        }
        catch { }
    }
}
'@
}

# Busca un servicio _adb-tls-* y devuelve @{ Name; Ip; Port } (o $null).
#   $kind: "pairing" | "connect"
#   $instancePrefix: si se da, solo instancias cuyo nombre empiece asi (el QR usa un nombre propio)
#   $ipFilter: si se da, solo servicios de esa IP
function Find-AdbService([string]$kind, [string]$instancePrefix, [string]$ipFilter, [string]$unicastIp) {
    $svc = "_adb-tls-$kind._tcp.local"
    $rows = @([MdnsLite]::Query($svc, 12, $unicastIp, 1500))
    $instances = @($rows | Where-Object { $_[1] -eq "PTR" -and $_[0] -eq $svc } | ForEach-Object { @{ Full = $_[2]; Sender = $_[3] } })
    foreach ($inst in $instances) {
        $short = ($inst.Full -split "\.")[0]
        if ($instancePrefix -and -not $short.StartsWith($instancePrefix)) { continue }
        $srv = $rows | Where-Object { $_[1] -eq "SRV" -and $_[0] -eq $inst.Full } | Select-Object -First 1
        if (-not $srv) {
            # La respuesta PTR no trajo el SRV: se pide aparte.
            $more = @([MdnsLite]::Query($inst.Full, 33, $inst.Sender, 1000))
            $srv = $more | Where-Object { $_[1] -eq "SRV" } | Select-Object -First 1
        }
        if (-not $srv) { continue }
        $ip = $srv[3]
        if ($ipFilter -and $ip -ne $ipFilter) { continue }
        return @{ Name = $short; Ip = $ip; Port = [int](($srv[2] -split ";")[0]) }
    }
    return $null
}
