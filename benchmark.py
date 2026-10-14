#!/usr/bin/env python3
import time

import numpy as np
from mpi4py import MPI


def run_benchmark():
    world_comm = MPI.COMM_WORLD
    world_rank = world_comm.Get_rank()
    world_size = world_comm.Get_size()
    hostname = MPI.Get_processor_name()

    print(f"[World Rank {world_rank:02d} @ {hostname}] Online.", flush=True)

    if world_size < 2:
        if world_rank == 0:
            print(
                "Error: Benchmark requires at least 2 ranks across 2 nodes.", flush=True
            )
        return

    all_hosts = world_comm.allgather((world_rank, hostname))
    node_map = {}
    for r, h in all_hosts:
        if h not in node_map:
            node_map[h] = []
        node_map[h].append(r)

    unique_nodes = list(node_map.keys())

    if len(unique_nodes) < 2:
        if world_rank == 0:
            print(
                "Error: All ranks are on the same node. Please run across at least 2 nodes.",
                flush=True,
            )
        return

    # Select primary sender (Rank 0 of Node 1) and receiver (First rank of Node 2)
    sender_rank = node_map[unique_nodes[0]][0]
    receiver_rank = node_map[unique_nodes[1]][0]

    if world_rank == 0:
        print(
            "============================================================", flush=True
        )
        print(
            "              MPI CROSS-NODE DATA BENCHMARK                 ", flush=True
        )
        print(f"Total World Size   : {world_size}", flush=True)
        print(
            f"Unique Nodes ({len(unique_nodes)}) : {', '.join(unique_nodes)}",
            flush=True,
        )
        print(
            f"Pairing Ranks      : World Rank {sender_rank} ({unique_nodes[0]}) --> World Rank {receiver_rank} ({unique_nodes[1]})",
            flush=True,
        )
        print(
            "============================================================", flush=True
        )

    # Split communicator: Pair group (color=1) vs Passive group (color=0)
    is_active = (world_rank == sender_rank) or (world_rank == receiver_rank)
    color = 1 if is_active else 0
    active_comm = world_comm.Split(color=color, key=world_rank)

    world_comm.Barrier()

    # Passive ranks exit early without interfering in barriers
    if not is_active:
        print(
            f"[World Rank {world_rank:02d} @ {hostname}] Passive rank idle. Exiting cleanly.",
            flush=True,
        )
        return

    active_rank = active_comm.Get_rank()  # 0 for sender, 1 for receiver

    # Payload configuration: 500 MB payload
    data_size_mb = 500
    num_elements = (data_size_mb * 1024 * 1024) // 8
    num_iterations = 5

    # Memory allocation for NumPy buffers
    if active_rank == 0:
        data = np.ones(num_elements, dtype=np.float64)
    else:
        data = np.empty(num_elements, dtype=np.float64)

    # Small ACK buffers for round-trip time verification
    ack_send = np.ones(1, dtype=np.int32)
    ack_recv = np.empty(1, dtype=np.int32)

    # Warmup transfer using blocking calls
    if active_rank == 0:
        active_comm.Send([data, MPI.DOUBLE], dest=1, tag=99)
        active_comm.Recv([ack_recv, MPI.INT], source=1, tag=999)
    else:
        active_comm.Recv([data, MPI.DOUBLE], source=0, tag=99)
        active_comm.Send([ack_send, MPI.INT], dest=0, tag=999)

    active_comm.Barrier()

    # Timed benchmark loop using blocking Send/Recv
    times = []
    for i in range(num_iterations):
        active_comm.Barrier()
        t0 = time.perf_counter()

        if active_rank == 0:
            active_comm.Send([data, MPI.DOUBLE], dest=1, tag=i)
            active_comm.Recv([ack_recv, MPI.INT], source=1, tag=i + 1000)
            t1 = time.perf_counter()
            times.append(t1 - t0)
        else:
            active_comm.Recv([data, MPI.DOUBLE], source=0, tag=i)
            active_comm.Send([ack_send, MPI.INT], dest=0, tag=i + 1000)

    if active_rank == 0:
        avg_time = sum(times) / len(times)
        data_gb = data_size_mb / 1024.0
        throughput_gbps = data_gb / avg_time
        bandwidth_gbps = (data_gb * 8) / avg_time

        print("\n--- BENCHMARK RESULTS ---", flush=True)
        for idx, t in enumerate(times, 1):
            print(f"Iteration {idx}: {t:.6f} s ({data_gb / t:.2f} GB/s)", flush=True)
        print(
            "------------------------------------------------------------", flush=True
        )
        print(f"Average Time       : {avg_time:.6f} s", flush=True)
        print(f"Throughput         : {throughput_gbps:.2f} GB/s", flush=True)
        print(f"Bandwidth          : {bandwidth_gbps:.2f} Gbps", flush=True)
        print(
            "============================================================", flush=True
        )


if __name__ == "__main__":
    run_benchmark()
