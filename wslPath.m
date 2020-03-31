function PathName = wslPath(PathName)

UnixName = strrep(PathName, '\', '/');
PathName = strrep(UnixName, 'C:', '/mnt/c');