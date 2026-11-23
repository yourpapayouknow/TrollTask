// 从系统已知时区中选择新任务的默认值。
final class TaskTimeZoneScreen: TaskScreen, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    private struct Option {
        let id: String
        let city: String
        let offset: String
        let seconds: Int
    }

    private let table = UITableView(frame: .zero, style: .plain)
    private let search = UISearchBar()
    private var options: [Option] = []
    private var matches: [Option] = []
    private var searching = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "任务时区"
        let back = tu_ibtn("back", "返回设置", "timezone.back", self, #selector(bck))
        let header = hdr(tu_lbl(title), back, nil)
        search.placeholder = "搜索城市"
        search.accessibilityIdentifier = "timezone.search"
        search.searchTextField.accessibilityIdentifier = "timezone.query"
        search.searchBarStyle = .minimal
        search.delegate = self
        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear
        table.keyboardDismissMode = .onDrag
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 72
        table.accessibilityIdentifier = "timezone.list"
        let stack = tu_stk([search, table])
        view.addSubview(stack)
        tu_wdth(stack, view, inset: 0)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: header.bottomAnchor),
                                     stack.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)])

        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "OOOO"
        let cities = DateFormatter()
        cities.locale = formatter.locale
        cities.dateFormat = "VVV"
        var ids = Set(TimeZone.knownTimeZoneIdentifiers + ["UTC"])
        if let selection = TaskTimeZone.selection { ids.insert(selection) }
        options = ids.compactMap { id in
            guard let zone = TimeZone(identifier: id) else { return nil }
            formatter.timeZone = zone
            return Option(id: id, city: TaskTimeZone.city(zone, cities, now), offset: formatter.string(from: now), seconds: zone.secondsFromGMT(for: now))
        }.sorted {
            if $0.seconds != $1.seconds { return $0.seconds < $1.seconds }
            let order = $0.city.localizedStandardCompare($1.city)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        matches = options
    }

    // 搜索只过滤列表，点选一行才保存。
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        searching = !query.isEmpty
        matches = searching ? options.filter {
            $0.city.localizedStandardContains(query) || $0.id.localizedStandardContains(query)
                || $0.offset.localizedStandardContains(query) || ($0.id == "Asia/Shanghai" && query == "北京")
        } : options
        table.reloadData()
        table.setContentOffset(.zero, animated: false)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }

    func numberOfSections(in tableView: UITableView) -> Int { searching ? 1 : 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        !searching && section == 0 ? 1 : max(1, matches.count)
    }

    // 用中文城市和当前UTC偏移区分固定时区。
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell()
        cell.backgroundColor = TaskTheme.base
        var content = tu_cell()
        let fixed = TaskTimeZone.fixed
        let selected: Bool
        if !searching && indexPath.section == 0 {
            content.text = "跟随系统"
            selected = fixed == nil
            cell.accessibilityIdentifier = "timezone.system"
        } else if matches.isEmpty {
            content.text = "无匹配时区"
            cell.selectionStyle = .none
            selected = false
        } else {
            let option = matches[indexPath.row]
            content.text = option.city
            content.secondaryText = option.offset
            selected = option.id == TaskTimeZone.selection
            cell.accessibilityIdentifier = "timezone." + option.id
        }
        if selected {
            cell.accessoryType = .checkmark
            cell.accessibilityTraits.insert(.selected)
        }
        cell.contentConfiguration = content
        return cell
    }

    // 立即保存选择并返回设置。
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if !searching && indexPath.section == 0 {
            UserDefaults.standard.removeObject(forKey: TaskTimeZone.key)
        } else {
            guard matches.indices.contains(indexPath.row) else { return }
            UserDefaults.standard.set(matches[indexPath.row].id, forKey: TaskTimeZone.key)
        }
        search.resignFirstResponder()
        bck()
    }
}