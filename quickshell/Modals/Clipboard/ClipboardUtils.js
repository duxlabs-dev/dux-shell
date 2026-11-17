.pragma library

function decodeEntryData(data) {
    if (!data)
        return "";
    if (typeof data !== "string")
        return String(data);

    const sanitized = data.replace(/\s+/g, "");
    if (sanitized.length === 0)
        return "";

    try {
        const decoded = Qt.atob(sanitized);
        if (!decoded)
            return data;

        let binary = "";
        if (typeof decoded === "string") {
            binary = decoded;
        } else {
            const bytes = new Uint8Array(decoded);
            const chunkSize = 8192;
            const chunks = [];
            for (let i = 0; i < bytes.length; i += chunkSize)
                chunks.push(String.fromCharCode.apply(null, bytes.subarray(i, i + chunkSize)));
            binary = chunks.join("");
        }

        if (!binary)
            return data;
        try {
            return decodeURIComponent(escape(binary));
        } catch (e) {
            return binary;
        }
    } catch (e) {
        return data;
    }
}
