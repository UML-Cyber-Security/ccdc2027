from collections import Counter
from dpkt import pcap, ethernet, ip, tcp, udp
from numpy import diff, mean, std
from socket import inet_ntoa

PCAP_FILE = 'received.pcap'
BATCH_THRESHOLD = 10
DEST_IP = '192.168.6.254'


def read_all_tcp_packets(pcap_file=PCAP_FILE):
    tcp_connections = {}

    with open(pcap_file, 'rb') as f:
        for ts, buf in pcap.Reader(f):
            eth = ethernet.Ethernet(buf)

            if isinstance(eth.data, ip.IP):
                packet = eth.data

                if isinstance(packet.data, tcp.TCP):
                    src_ip = inet_ntoa(packet.src)
                    dst_ip = inet_ntoa(packet.dst)
                    dst_port = packet.data.dport

                    tcp_flags = packet.data.flags
                    if (tcp_flags & tcp.TH_SYN) and \
                            (DEST_IP == '' or DEST_IP == dst_ip):
                        key = (src_ip, dst_ip, dst_port)

                        if key not in tcp_connections:
                            tcp_connections[key] = {'timestamps': []}

                        prev_ts = 0
                        if len(tcp_connections[key]['timestamps']) > 0:
                            prev_ts = tcp_connections[key]['timestamps'][-1]

                        if ts - prev_ts > BATCH_THRESHOLD:
                            tcp_connections[key]['timestamps'].append(ts)

    return tcp_connections


def format_tcp_packets(tcp_packets):
    for key, data in tcp_packets.items():
        src_ip, dst_ip, dst_port = key
        timestamps = data['timestamps']

        mean_diff = 0.0
        std_diff = 0.0
        if len(timestamps) > 1:
            diffs = diff(sorted(timestamps))
            mean_diff = mean(diffs)
            std_diff = std(diffs)

        print(f"Connection: {src_ip} -> {dst_ip}:{dst_port}")
        print(f"  Packets Difference (Mean): {mean_diff:.6f} sec")
        print(f"  Packets Difference (STD): {std_diff:.6f} sec")
        print(f"  Total Packets Received: {len(timestamps)}")
        print(f"  Total Duration of Packets: {timestamps[-1] - timestamps[0]}")
        print()


def read_all_udp_packets(pcap_file=PCAP_FILE):
    udp_connections = {}

    with open(pcap_file, 'rb') as f:
        for ts, buf in pcap.Reader(f):
            eth = ethernet.Ethernet(buf)

            if isinstance(eth.data, ip.IP):
                packet = eth.data

                if isinstance(packet.data, udp.UDP):
                    src_ip = inet_ntoa(packet.src)
                    dst_ip = inet_ntoa(packet.dst)
                    dst_port = packet.data.dport
                    length = len(packet)

                    if DEST_IP == '' or DEST_IP == dst_ip:
                        key = (src_ip, dst_ip, dst_port)

                        if key not in udp_connections:
                            udp_connections[key] = {
                                'lengths': [],
                                'timestamps': []
                            }

                        udp_connections[key]['lengths'].append(length)

                        prev_ts = 0
                        if len(udp_connections[key]['timestamps']) > 0:
                            prev_ts = udp_connections[key]['timestamps'][-1]

                        if ts - prev_ts > BATCH_THRESHOLD:
                            udp_connections[key]['timestamps'].append(ts)

    return udp_connections


def format_udp_packets(udp_packets):
    for key, data in udp_packets.items():
        src_ip, dst_ip, dst_port = key
        lengths = data['lengths']
        timestamps = data['timestamps']

        mean_diff = 0.0
        std_diff = 0.0
        if len(timestamps) > 1:
            diffs = diff(sorted(timestamps))
            mean_diff = mean(diffs)
            std_diff = std(diffs)

        print(f"Connection: {src_ip} -> {dst_ip}:{dst_port}")
        print(f"  Packets Difference (Mean): {mean_diff:.6f} sec")
        print(f"  Packets Difference (STD): {std_diff:.6f} sec")
        print(f"  Packets Lengths: {list(Counter(lengths).items())}")
        print(f"  Total Duration of Packets: {timestamps[-1] - timestamps[0]}")
        print()


if __name__ == '__main__':

    udp_packets = read_all_udp_packets()
    format_udp_packets(udp_packets)
