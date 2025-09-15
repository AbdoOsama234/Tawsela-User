import 'dart:convert';
import 'package:http/http.dart' as http;
class RequestAssistants{

  static Future<dynamic> receiveRequest(String url) async{
    http.Response httpResponse=  await http.get(Uri.parse(url));

    try{
      if(httpResponse.statusCode==200)  //successful
      {
        String responseData=httpResponse.body; //json
        var decodeResponseData=jsonDecode(responseData);

        return decodeResponseData;
      }
      else{
        return null;
      }
    }catch(exp){
      return "Error Occured. Failed. No Response";

    }
  }
}