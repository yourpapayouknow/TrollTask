// 把当天真实区间映射到连续刻度，同一时刻并行使用独立列。
@objc(TaskTimeMap) final class TaskTimeMap: NSObject {
    // 生成平台无关的可验证几何数据。
    @objc(map:width:scale:error:) static func map(_ plan: NSDictionary, width: Double, scale: Double) throws -> NSDictionary {
        guard width.isFinite, (100...5000).contains(width), scale.isFinite, (1...100).contains(scale), let lo = plan["day_at"] as? NSNumber, let hi = plan["day_end"] as? NSNumber,
              ts_num(lo), ts_num(hi), hi.doubleValue > lo.doubleValue, hi.doubleValue-lo.doubleValue <= 93600, let entries = plan["entries"] as? [TaskFields], entries.count <= 10000 else { throw TaskAI.err("时间轴数据无效") }
        let start = lo.doubleValue, end = hi.doubleValue, gutter = 64.0, gap = 4.0
        var frames = Array(repeating:[Double](), count:entries.count), lanes = Array(repeating:0,count:entries.count), columns = Array(repeating:1,count:entries.count)
        var normal: [Int] = []
        for (index,row) in entries.enumerated() {
            guard let a = row["start_at"] as? NSNumber, let b = row["end_at"] as? NSNumber, ts_num(a), ts_num(b), a.doubleValue >= start, b.doubleValue <= end, b.doubleValue >= a.doubleValue else { throw TaskAI.err("时间轴区间无效") }
            frames[index] = [gutter,(a.doubleValue-start)/60*scale,width-gutter,max(1,(b.doubleValue-a.doubleValue)/60*scale)]
            if !["work","rest"].contains(row["kind"] as? String ?? "") { normal.append(index) }
        }
        normal.sort { a,b in let first = (entries[a]["start_at"] as! NSNumber).doubleValue, second = (entries[b]["start_at"] as! NSNumber).doubleValue; return first == second ? a < b : first < second }
        var group: [Int] = [], laneEnds: [Double] = [], groupEnd = -Double.infinity
        // 只按真实区间划分并行列，不拉长或平移任务。
        func finish() {
            let count = max(1,laneEnds.count), cellWidth = (width-gutter-gap*Double(count-1))/Double(count)
            for index in group { columns[index] = count; frames[index][0] = gutter+Double(lanes[index])*(cellWidth+gap); frames[index][2] = cellWidth }
        }
        for index in normal {
            let a = (entries[index]["start_at"] as! NSNumber).doubleValue, b = (entries[index]["end_at"] as! NSNumber).doubleValue
            if a >= groupEnd { finish();group=[];laneEnds=[];groupEnd = -Double.infinity }
            let lane = laneEnds.firstIndex(where:{$0 <= a}) ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(b) } else { laneEnds[lane] = b }
            lanes[index] = lane;group.append(index);groupEnd = max(groupEnd,b)
        };finish()
        let contentWidth = max(width,gutter+Double(columns.max() ?? 1)*96+Double(max(0,(columns.max() ?? 1)-1))*gap)
        for index in entries.indices {
            let count = columns[index], localWidth = ["work","rest"].contains(entries[index]["kind"] as? String ?? "") ? contentWidth : max(width,gutter+Double(count)*96+Double(count-1)*gap)
            let cellWidth = (localWidth-gutter-gap*Double(count-1))/Double(count)
            frames[index][0] = gutter+Double(lanes[index])*(cellWidth+gap);frames[index][2] = cellWidth
        }
        return ["width":contentWidth,"frames":frames,"lanes":lanes,"columns":columns,"height":(end-start)/60*scale+32,"gutter":gutter,
                "ticks":stride(from:start,through:end,by:3600).map{$0},"day_at":start,"day_end":end,"scale":scale]
    }
}
