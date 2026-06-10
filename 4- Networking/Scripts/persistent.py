from dpkt import pcap, ethernet, ip, tcp
from socket import inet_ntoa


PCAP_FILE = 'reverse.pcap'


def read_all_tcp_packets(pcap_file=PCAP_FILE):
    connections = {}

    with open(pcap_file, 'rb') as f:
        for ts, buf in pcap.Reader(f):
            eth = ethernet.Ethernet(buf)

            if isinstance(eth.data, ip.IP):
                packet = eth.data

                if isinstance(packet.data, tcp.TCP):
                    src_ip = inet_ntoa(packet.src)
                    src_port = packet.data.sport
                    dst_ip = inet_ntoa(packet.dst)
                    dst_port = packet.data.dport

                    key = (src_ip, src_port, dst_ip, dst_port)
                    connections.setdefault(key, []).append(ts)

    return connections


def format_tcp_connections(connections):
    data = []

    for conn, ts in connections.items():
        src_ip, src_port, dst_ip, dst_port = conn
        total_packets = len(ts)
        duration = ts[-1] - ts[0] if len(ts) > 1 else 0
        data.append((conn, total_packets, duration, ts[0], ts[-1]))

    data.sort(key=lambda x: x[2], reverse=True)

    for conn, total_packets, duration, first_ts, last_ts in data:
        src_ip, src_port, dst_ip, dst_port = conn
        print(f"Connection: {src_ip}:{src_port} -> {dst_ip}:{dst_port}")
        print(f"  Total Packets: {total_packets}")
        print(f"  Duration: {duration:.2f} seconds")
        print(f"  First Packet: {first_ts}")
        print(f"  Last Packet: {last_ts}")
        print()


if __name__ == '__main__':
    connections = read_all_tcp_packets()
    format_tcp_connections(connections)
