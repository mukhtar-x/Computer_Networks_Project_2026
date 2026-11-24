import time


class MacTable:
    def __init__(self, aging=300):
        self.aging = aging
        self.entries = {}

    def expire(self, now=None):
        now = time.time() if now is None else now
        stale = [key for key, (_, seen) in self.entries.items() if now - seen >= self.aging]
        for key in stale:
            del self.entries[key]

    def learn(self, vlan, mac, port, now=None):
        now = time.time() if now is None else now
        self.expire(now)
        self.entries[(vlan, mac)] = (port, now)

    def lookup(self, vlan, mac, now=None):
        now = time.time() if now is None else now
        entry = self.entries.get((vlan, mac))
        if entry is None:
            return None
        if now - entry[1] >= self.aging:
            del self.entries[(vlan, mac)]
            return None
        return entry[0]

    def rows(self, now=None):
        self.expire(now)
        return sorted((vlan, mac, port, seen) for (vlan, mac), (port, seen) in self.entries.items())
