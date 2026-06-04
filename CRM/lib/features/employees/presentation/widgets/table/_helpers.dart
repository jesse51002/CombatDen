/// "12 / wk" for coaches; an em dash for staff who don't teach.
String classesPerWeekLabel(int? classesPerWeek) =>
    classesPerWeek == null ? '—' : '$classesPerWeek / wk';
